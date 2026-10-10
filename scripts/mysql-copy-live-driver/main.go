// Isolated-fixture adapter: real NativeDriver and KubeTransport, no CP lease claim.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/envplane/runner/internal/mysqlcopy"
)

type config struct {
	RunID              string
	Kubeconfig         string
	ClusterUID         string
	SourceNamespaceUID string
	TargetNamespaceUID string
	Plan               mysqlcopy.Plan
	Fences             []mysqlcopy.AdmissionFenceRef
	Journal            string
	Mode               string
}

func (c config) src() string { return "mysqlcopy-live-" + c.RunID + "-src" }
func (c config) dst() string { return "mysqlcopy-live-" + c.RunID + "-dst" }
func (c config) validate() error {
	if !regexp.MustCompile(`^[a-f0-9]{16}$`).MatchString(c.RunID) || c.ClusterUID != "49918e1f-d1f7-4aba-9afb-a4cea4187822" || c.SourceNamespaceUID == "" || c.TargetNamespaceUID == "" || c.Kubeconfig == "" || c.Plan.Source.PVC.Namespace != c.src() || c.Plan.Target.Namespace != c.dst() || len(c.Fences) != 1 {
		return errors.New("invalid isolated fixture identity")
	}
	if c.Mode != "positive" && c.Mode != "retry" && c.Mode != "cancel" {
		return errors.New("invalid fixture mode")
	}
	return c.Plan.Validate()
}

type commands struct {
	c                 config
	cancel            context.CancelFunc
	transferred       int64
	restoreAttempted  bool
	ddlProven         bool
	sourceUIDMismatch bool
}

func (k *commands) argv(args []string, probe bool) []string {
	out := []string{"--kubeconfig", k.c.Kubeconfig, "--context", "kind-envplane-readiness-682", "--as", "system:serviceaccount:" + k.c.dst() + ":copy-runner"}
	// Admission evaluates the real Runner principal; positive spec uses source default SA.
	return append(out, args...)
}
func (k *commands) journal(args []string, err error, probe bool, denial string) error {
	if k.c.Journal == "" {
		return nil
	}
	f, e := os.OpenFile(k.c.Journal, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		return e
	}
	defer f.Close()
	// Never retain SQL argv, Secret data, SQL dumps, config, stdin, or arbitrary stderr.
	verb := "unknown"
	if len(args) > 0 {
		verb = args[0]
	}
	e = json.NewEncoder(f).Encode(map[string]any{"verb": verb, "success": err == nil, "admissionProbe": probe, "denial": denial, "payload": "not retained"})
	return errors.Join(e, f.Sync())
}
func (k *commands) run(ctx context.Context, args []string, in io.Reader, out io.Writer, probe bool) error {
	cmd := exec.CommandContext(ctx, "kubectl", k.argv(args, probe)...)
	var diagnostic bytes.Buffer
	cmd.Stdin = in
	cmd.Stdout = out
	cmd.Stderr = &diagnostic
	cmd.WaitDelay = 2 * time.Second
	err := cmd.Run()
	denial := ""
	if probe {
		// Only admission-probe stderr is returned to native exact Deny validation.
		_, _ = out.Write(diagnostic.Bytes())
		for _, line := range strings.Split(diagnostic.String(), "\n") {
			if strings.Contains(line, "ValidatingAdmissionPolicy") && len(line) < 4096 {
				denial = line
			}
		}
	}
	if e := k.journal(args, err, probe, denial); e != nil {
		return e
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err != nil {
		return errors.New("fixture kubectl operation failed; payload redacted")
	}
	return nil
}
func (k *commands) Run(ctx context.Context, args []string, in io.Reader, out io.Writer) error {
	if len(args) >= 3 && args[0] == "get" && args[1] == "pvc" && args[2] == k.c.Plan.Source.PVC.Name {
		var metadata bytes.Buffer
		err := k.run(ctx, args, in, io.MultiWriter(out, &metadata), false)
		if err == nil {
			var o struct{ Metadata struct{ UID string } }
			if json.Unmarshal(metadata.Bytes(), &o) == nil && o.Metadata.UID != "" && o.Metadata.UID != k.c.Plan.Source.PVC.UID {
				k.sourceUIDMismatch = true
			}
		}
		return err
	}
	return k.run(ctx, args, in, out, false)
}

type transport struct {
	*mysqlcopy.KubeTransport
	k *commands
}

func nativeTransport(c config, k *commands) *transport {
	driver := mysqlcopy.NewProofDriver(mysqlcopy.DriverConfig{Commands: k, RunnerImage: c.Plan.ConfigImage, MySQLImage: c.Plan.Source.Image, ServiceAccount: "default", AllowRootInit: true, SourceAdmissionFences: c.Fences, Authorize: k.authority})
	return &transport{KubeTransport: &mysqlcopy.KubeTransport{Driver: driver, Commands: k, SourceNamespaces: []string{c.src()}, RunnerImage: c.Plan.ConfigImage, MySQLImage: c.Plan.Source.Image}, k: k}
}

func (t *transport) Restore(ctx context.Context, p mysqlcopy.Plan, id mysqlcopy.TargetIdentity, r io.Reader) error {
	t.k.restoreAttempted = true
	if t.k.c.Mode == "cancel" {
		r = &cancelReader{r: r, k: t.k, remaining: 1024}
	}
	return t.KubeTransport.Restore(ctx, p, id, r)
}
func (k *commands) RunAdmissionFenceProbe(ctx context.Context, args []string, in io.Reader, out io.Writer) error {
	return k.run(ctx, args, in, out, true)
}

type cancelReader struct {
	r         io.Reader
	k         *commands
	remaining int
}

func (r *cancelReader) Read(p []byte) (int, error) {
	if r.remaining <= 0 {
		r.k.cancel()
		return 0, context.Canceled
	}
	if len(p) > r.remaining {
		p = p[:r.remaining]
	}
	n, e := r.r.Read(p)
	r.remaining -= n
	r.k.transferred += int64(n)
	return n, e
}
func (k *commands) authority(ctx context.Context, p mysqlcopy.Plan, s mysqlcopy.Stage) error {
	if p.Source.PVC.Namespace != k.c.src() || p.Target.Namespace != k.c.dst() {
		return mysqlcopy.ErrUnsafe
	}
	// Cluster identity is read with fixture-owner credentials, never granted broadly to SA.
	for ns, uid := range map[string]string{"kube-system": k.c.ClusterUID, k.c.src(): k.c.SourceNamespaceUID, k.c.dst(): k.c.TargetNamespaceUID} {
		cmd := exec.CommandContext(ctx, "kubectl", "--kubeconfig", k.c.Kubeconfig, "--context", "kind-envplane-readiness-682", "get", "namespace", ns, "-o", "jsonpath={.metadata.uid}")
		got, e := cmd.Output()
		if e != nil || string(got) != uid {
			return mysqlcopy.ErrUnsafe
		}
	}
	if s == mysqlcopy.Transfer && !k.ddlProven {
		// Transfer is reached only after native HoldDDL acquisition. Root diagnostic
		// Pod is new fixture-owned, never the source workload or a baseline database.
		query := func(sql string) (string, string, error) {
			args := []string{"--kubeconfig", k.c.Kubeconfig, "--context", "kind-envplane-readiness-682", "exec", "diagnostics", "-n", k.c.src(), "-c", "mysql", "--", "mysql", "--defaults-extra-file=/config/app.cnf", "--host=" + p.Source.TLSServerName, "--ssl-mode=VERIFY_IDENTITY", "--ssl-ca=/credentials/ca.pem", "--batch", "--skip-column-names", "-e", sql}
			cmd := exec.CommandContext(ctx, "kubectl", args...)
			var out, stderr bytes.Buffer
			cmd.Stdout = &out
			cmd.Stderr = &stderr
			err := cmd.Run()
			return strings.TrimSpace(out.String()), stderr.String(), err
		}
		before, _, e := query("SELECT COUNT(*) FROM fixturedb.records")
		if e != nil {
			return mysqlcopy.ErrUnsafe
		}
		_, diagnostic, e := query("SET SESSION lock_wait_timeout=2; ALTER TABLE fixturedb.records ADD COLUMN forbidden_live_probe INT")
		if e == nil || !strings.Contains(diagnostic, "ERROR 1205") {
			return mysqlcopy.ErrUnsafe
		}
		after, _, e := query("SELECT COUNT(*) FROM fixturedb.records")
		if e != nil {
			return mysqlcopy.ErrUnsafe
		}
		var a, b int64
		if _, e = fmt.Sscan(before, &a); e != nil {
			return mysqlcopy.ErrUnsafe
		}
		if _, e = fmt.Sscan(after, &b); e != nil || b <= a {
			return mysqlcopy.ErrUnsafe
		}
		k.ddlProven = true
		if k.c.Journal != "" {
			f, e := os.OpenFile(k.c.Journal, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
			if e != nil {
				return e
			}
			e = json.NewEncoder(f).Encode(map[string]any{"DDLBlockedByBackupLock": true, "mysqlError": 1205, "writerRowsBefore": a, "writerRowsAfter": b})
			_ = f.Close()
			if e != nil {
				return e
			}
		}
	}
	return nil
}
func certificates(dns string) (map[string]string, error) {
	if !regexp.MustCompile(`^mysql\.mysqlcopy-live-[a-f0-9]{16}-src\.svc$`).MatchString(dns) {
		return nil, errors.New("invalid fixture DNS")
	}
	caKey, e := rsa.GenerateKey(rand.Reader, 2048)
	if e != nil {
		return nil, e
	}
	key, e := rsa.GenerateKey(rand.Reader, 2048)
	if e != nil {
		return nil, e
	}
	now := time.Now()
	ca := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "isolated-fixture-ca"}, NotBefore: now.Add(-time.Minute), NotAfter: now.Add(6 * time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature}
	der, e := x509.CreateCertificate(rand.Reader, ca, ca, &caKey.PublicKey, caKey)
	if e != nil {
		return nil, e
	}
	server := &x509.Certificate{SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: dns}, DNSNames: []string{dns}, NotBefore: ca.NotBefore, NotAfter: ca.NotAfter, KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	cert, e := x509.CreateCertificate(rand.Reader, server, ca, &key.PublicKey, caKey)
	if e != nil {
		return nil, e
	}
	return map[string]string{"ca": string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})), "cert": string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert})), "key": string(pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)}))}, nil
}
func main() {
	if len(os.Args) == 3 && os.Args[1] == "certificates" {
		v, e := certificates(os.Args[2])
		if e != nil {
			fmt.Fprintln(os.Stderr, e)
			os.Exit(2)
		}
		_ = json.NewEncoder(os.Stdout).Encode(v)
		return
	}
	var c config
	dec := json.NewDecoder(io.LimitReader(os.Stdin, 1<<20))
	dec.DisallowUnknownFields()
	if dec.Decode(&c) != nil || c.validate() != nil {
		fmt.Fprintln(os.Stderr, "invalid fixture metadata")
		os.Exit(2)
	}
	if len(os.Args) == 2 && os.Args[1] == "source-probe" {
		spec, e := mysqlcopy.SourceClientHelperSpec(c.Plan, "default")
		if e != nil {
			os.Exit(2)
		}
		_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"apiVersion": "v1", "kind": "Pod", "metadata": map[string]any{"name": mysqlcopy.SourceClientHelperName(c.Plan.Source.PVC), "namespace": c.src(), "labels": map[string]any{"envplane.io/managed": "true", "envplane.io/project": c.Plan.Project, "envplane.io/environment": c.Plan.Environment}}, "spec": spec})
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	k := &commands{c: c, cancel: cancel}
	t := nativeTransport(c, k)
	receipt, e := (mysqlcopy.DomainExecutor{Transport: t, Authority: k.authority}).ExecuteDomain(ctx, c.Plan)
	digest, _ := c.Plan.Digest()
	sum := sha256.Sum256([]byte(digest))
	result := map[string]any{"success": e == nil, "receipt": receipt, "restoreAttempted": k.restoreAttempted, "cancelInputBytes": k.transferred, "planDigest": digest, "metadataSHA256": hex.EncodeToString(sum[:]), "DDLBlockedByBackupLock": k.ddlProven, "sourceUIDMismatchObserved": k.sourceUIDMismatch, "CPLeaseProven": false}
	if e != nil {
		result["error"] = e.Error()
	}
	_ = json.NewEncoder(os.Stdout).Encode(result)
	if e != nil {
		os.Exit(1)
	}
}
