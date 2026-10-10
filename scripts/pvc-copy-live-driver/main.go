// Fixture-only host adapter. It exercises real Runner code, not the CP lease/UI.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync/atomic"
	"time"

	"github.com/envplane/contracts/domain"
	"github.com/envplane/runner/internal/pvccopy"
)

type config struct {
	RunID              string `json:"runID"`
	Kubeconfig         string `json:"kubeconfig"`
	Context            string `json:"context"`
	ClusterUID         string `json:"clusterUID"`
	SourceUID          string `json:"sourceUID"`
	SourceNamespaceUID string `json:"sourceNamespaceUID"`
	TargetNamespaceUID string `json:"targetNamespaceUID"`
	SourceName         string `json:"sourceName"`
	TargetName         string `json:"targetName"`
	StorageClass       string `json:"storageClass"`
	Image              string `json:"image"`
	Mode               string `json:"mode"`
	HelperBinarySHA256 string `json:"helperBinarySHA256"`
	CommandJournal     string `json:"commandJournal"`
}

func (c config) sourceNS() string  { return "pvccopy-live-" + c.RunID + "-src" }
func (c config) targetNS() string  { return "pvccopy-live-" + c.RunID + "-dst" }
func (c config) principal() string { return "system:serviceaccount:" + c.targetNS() + ":copy-runner" }
func (c config) validate() error {
	if !regexp.MustCompile(`^[a-f0-9]{16}$`).MatchString(c.RunID) || c.Context != "kind-envplane-readiness-682" || c.ClusterUID == "" || c.Kubeconfig == "" || c.SourceUID == "" || (c.SourceName != "source" && c.SourceName != "uid-probe") {
		return errors.New("invalid isolated fixture identity")
	}
	switch c.TargetName {
	case "copy-positive", "copy-cancel", "copy-uid":
	default:
		return errors.New("invalid fixture target")
	}
	return nil
}
func compile(c config) (domain.PVCCopyPlan, domain.PVCCopySource, domain.PVCCopyPermission, error) {
	s := domain.PVCCopySource{TenantID: "default", Namespace: c.sourceNS(), Name: c.SourceName, UID: c.SourceUID, StorageClass: c.StorageClass, AccessModes: []string{"ReadWriteOnce"}, RequestedBytes: 64 << 20, VolumeMode: "Filesystem", EnvironmentClass: "test"}
	h := sha256.Sum256([]byte(c.RunID))
	p := domain.PVCCopyPlan{PlanID: c.RunID + "-" + c.TargetName, TenantID: "default", ProjectID: "pvccopy-live-" + c.RunID, EnvironmentID: c.TargetName, TemplateRevisionID: "fixture-v1", TemplateDigest: "sha256:" + hex.EncodeToString(h[:]), TargetNamespace: c.targetNS(), AllowedSourceNamespaces: []string{c.sourceNS()}, Image: c.Image, MaxBytes: 64 << 20, TimeoutSeconds: 120, StorageQuotaBytes: 64 << 20, Items: []domain.PVCCopyItem{{ID: "data", SourceTenantID: s.TenantID, SourceNamespace: s.Namespace, SourceName: s.Name, SourceUID: s.UID, SourceRequestedBytes: s.RequestedBytes, TargetName: c.TargetName, StorageClass: s.StorageClass, AccessModes: s.AccessModes, RequestedBytes: 64 << 20, Method: domain.PVCCopyFilesystemOffline, MaxBytes: 64 << 20, TimeoutSeconds: 120}}}
	permission := domain.PVCCopyPermission{PlanID: p.PlanID, TenantID: p.TenantID, ProjectID: p.ProjectID, EnvironmentID: p.EnvironmentID, TemplateRevisionID: p.TemplateRevisionID, TemplateDigest: p.TemplateDigest, TargetNamespace: p.TargetNamespace, AllowedSourceNamespaces: p.AllowedSourceNamespaces, AllowedImages: []string{p.Image}, MaxBytes: p.MaxBytes, TimeoutSeconds: p.TimeoutSeconds, StorageQuotaBytes: p.StorageQuotaBytes}
	p, err := domain.CompilePVCCopyPlan(p, []domain.PVCCopySource{s}, permission)
	return p, s, permission, err
}

// Every native kubectl call carries an explicit isolated context and fixture SA.
type commands struct {
	c           config
	cancel      context.CancelFunc
	interrupted atomic.Int64
}

func (k *commands) args(args []string) []string {
	return append([]string{"--kubeconfig", k.c.Kubeconfig, "--context", k.c.Context, "--as", k.c.principal()}, args...)
}
func (k *commands) record(args []string, err error, evidence any) {
	if k.c.CommandJournal == "" {
		return
	}
	file, e := os.OpenFile(k.c.CommandJournal, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		return
	}
	defer file.Close()
	_ = json.NewEncoder(file).Encode(map[string]any{"command": append([]string{"kubectl"}, k.args(args)...), "success": err == nil, "evidence": evidence, "payload": "not recorded"})
}
func (k *commands) Run(ctx context.Context, args []string, in io.Reader, out io.Writer) (retErr error) {
	var captured bytes.Buffer
	if !slicesContain(args, "pvc-export") {
		out = io.MultiWriter(out, &captured)
	}
	defer func() {
		var evidence any
		if json.Unmarshal(captured.Bytes(), &evidence) != nil {
			evidence = nil
		}
		k.record(args, retErr, evidence)
	}()
	if len(args) > 0 && args[0] == "exec" {
		// A digest pin alone does not prove this host build is in the helper.
		// Hash its binary inside each freshly validated helper before any RPC.
		index := -1
		for i, arg := range args {
			if arg == "--" {
				index = i
				break
			}
		}
		if index < 0 {
			return errors.New("unexpected helper exec argv")
		}
		check := append(append([]string(nil), args[:index+1]...), "sha256sum", pvccopy.HelperBinary)
		var hash bytes.Buffer
		if err := (pvccopy.OSKubectl{}).Run(ctx, k.args(check), nil, &hash); err != nil {
			k.record(check, err, nil)
			return err
		}
		fields := strings.Fields(hash.String())
		if len(fields) != 2 || fields[0] != k.c.HelperBinarySHA256 {
			k.record(check, errors.New("mismatch"), nil)
			return errors.New("helper binary differs from reviewed host build")
		}
		k.record(check, nil, map[string]any{"helperBinarySHA256": fields[0], "matched": true})
	}
	if k.c.Mode == "cancel" && in != nil && slicesContain(args, "pvc-import") {
		in = &interruptReader{reader: in, ctx: ctx, k: k, remaining: 8192}
	}
	return (pvccopy.OSKubectl{}).Run(ctx, k.args(args), in, out)
}
func slicesContain(args []string, part string) bool {
	for _, a := range args {
		if a == part {
			return true
		}
	}
	return false
}
func (k *commands) RunAdmissionFenceProbe(ctx context.Context, args []string, in io.Reader, out io.Writer) error {
	if !slicesContain(args, "--dry-run=server") {
		return errors.New("probe must be server dry-run")
	}
	cmd := exec.CommandContext(ctx, "kubectl", k.args(args)...)
	cmd.Stdin = in
	cmd.Stdout = io.Discard
	var denial bytes.Buffer
	cmd.Stderr = io.MultiWriter(out, &denial)
	cmd.WaitDelay = 2 * time.Second
	err := cmd.Run()
	var lines []string
	for _, line := range strings.Split(denial.String(), "\n") {
		if strings.Contains(line, "ValidatingAdmissionPolicy '") {
			lines = append(lines, line)
		}
	}
	k.record(args, err, map[string]any{"serverDryRun": true, "policyDenial": lines})
	return err
}

// Stop after a bounded prefix has been delivered to a real live import process.
// Cancellation is only acceptance if later readback proves claim/no completion.
type interruptReader struct {
	reader    io.Reader
	ctx       context.Context
	k         *commands
	remaining int
}

func (r *interruptReader) Read(b []byte) (int, error) {
	if r.remaining == 0 {
		select {
		case <-r.ctx.Done():
			return 0, r.ctx.Err()
		case <-time.After(500 * time.Millisecond):
			r.k.cancel()
			<-r.ctx.Done()
			return 0, r.ctx.Err()
		}
	}
	if len(b) > r.remaining {
		b = b[:r.remaining]
	}
	n, e := r.reader.Read(b)
	r.remaining -= n
	r.k.interrupted.Add(int64(n))
	return n, e
}
func get(ctx context.Context, k *commands, args []string) (map[string]any, error) {
	var buf bytes.Buffer
	if err := k.Run(ctx, args, nil, &buf); err != nil {
		return nil, err
	}
	if buf.Len() > 1<<20 {
		return nil, errors.New("oversized metadata response")
	}
	var obj map[string]any
	err := json.Unmarshal(buf.Bytes(), &obj)
	return obj, err
}
func metadata(obj map[string]any) map[string]any { m, _ := obj["metadata"].(map[string]any); return m }
func checkNamespaces(ctx context.Context, k *commands) error {
	cluster, err := get(ctx, k, []string{"get", "namespace", "kube-system", "-o", "json", "--request-timeout=20s"})
	if err != nil {
		return err
	}
	if metadata(cluster)["uid"] != k.c.ClusterUID {
		return errors.New("cluster identity mismatch")
	}
	for _, pair := range []struct{ name, uid string }{{k.c.sourceNS(), k.c.SourceNamespaceUID}, {k.c.targetNS(), k.c.TargetNamespaceUID}} {
		obj, e := get(ctx, k, []string{"get", "namespace", pair.name, "-o", "json", "--request-timeout=20s"})
		if e != nil {
			return e
		}
		m := metadata(obj)
		labels, _ := m["labels"].(map[string]any)
		if pair.uid == "" || m["uid"] != pair.uid || m["deletionTimestamp"] != nil || labels["envplane.io/pvc-copy-live-run"] != k.c.RunID {
			return errors.New("fixture namespace identity mismatch")
		}
	}
	return nil
}
func audit(ctx context.Context, k *pvccopy.Kubectl, c config, p domain.PVCCopyPlan) (result any, retErr error) {
	ref := pvccopy.PVCRef{Namespace: c.sourceNS(), Name: c.SourceName, UID: c.SourceUID}
	if c.Mode == "audit-target" || c.Mode == "inspect-partial" {
		ref = pvccopy.PVCRef{Namespace: c.targetNS(), Name: c.TargetName}
	}
	live, e := k.GetPVC(ctx, ref)
	if e != nil {
		return nil, e
	}
	if ref.UID != "" && ref.UID != live.Ref.UID {
		return nil, pvccopy.ErrUnsafe
	}
	ref = live.Ref
	pods, e := k.ListPods(ctx, ref.Namespace)
	if e != nil {
		return nil, e
	}
	for _, pod := range pods {
		for _, claim := range pod.Claims {
			if claim == ref.Name && pod.Phase != "Succeeded" && pod.Phase != "Failed" {
				return nil, errors.New("audit requires idle fixture")
			}
		}
	}
	if ref.Namespace == c.sourceNS() {
		if !live.OfflineDeclared {
			return nil, pvccopy.ErrUnsafe
		}
		if e := k.CheckControllers(ctx, ref); e != nil {
			return nil, e
		}
	}
	h, e := k.CreateHelper(ctx, pvccopy.HelperSpec{Namespace: ref.Namespace, Name: pvccopy.SourceHelperName(ref), Owner: "fixture-audit-" + c.RunID, PVC: ref, ReadOnly: true, Image: c.Image, Timeout: 120 * time.Second})
	if h.UID != "" {
		defer func() {
			cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
			defer cancel()
			retErr = errors.Join(retErr, k.DeleteHelper(cleanup, h))
		}()
	}
	if e != nil {
		return nil, e
	}
	if e = k.WaitReady(ctx, h); e != nil {
		return nil, e
	}
	leaf := pvccopy.Plan{ImmutablePlanDigest: p.Digest, ItemID: "data", Tenant: p.TenantID, Project: p.ProjectID, Environment: p.EnvironmentID, Source: pvccopy.PVCRef{Namespace: c.sourceNS(), Name: c.SourceName, UID: c.SourceUID}, Target: pvccopy.PVCRef{Namespace: c.targetNS(), Name: c.TargetName, UID: "audit-not-created"}, MaxBytes: 64 << 20, MaxEntries: pvccopy.MaxCopyEntries, Timeout: 120 * time.Second, Image: c.Image, AllowedSourceNamespaces: p.AllowedSourceNamespaces, SourceQuiescedOffline: true}
	if ref.Namespace == c.targetNS() {
		leaf.Target = ref
	}
	leaf.AllowedTarget = pvccopy.TargetBinding{Tenant: leaf.Tenant, Project: leaf.Project, Environment: leaf.Environment, PVC: leaf.Target}
	raw, _ := json.Marshal(leaf)
	if c.Mode == "audit-source" {
		reader, writer := io.Pipe()
		done := make(chan error, 1)
		go func() {
			err := k.Exec(ctx, h, []string{pvccopy.HelperBinary, "pvc-export", string(raw)}, nil, writer)
			done <- errors.Join(err, writer.CloseWithError(err))
		}()
		receipt, e := pvccopy.Relay(ctx, leaf, reader, io.Discard)
		_ = reader.CloseWithError(e)
		return receipt, errors.Join(e, <-done)
	}
	var out bytes.Buffer
	if c.Mode == "inspect-partial" {
		// Fixture state only, read-only mount; no payload or credential output.
		// The native Exec intentionally permits only pvc-* RPCs. Do not weaken
		// it. This fixed read-only diagnostic uses the exact helper just created
		// and shape/UID-validated by CreateHelper + WaitReady, in our target only.
		e = k.Commands.Run(ctx, []string{"exec", "-n", h.Namespace, h.Name, "-c", "copy", "--", "sh", "-c", "test -f /data/.envplane-pvccopy/claim.json && test ! -e /data/.envplane-pvccopy/complete.json && printf partial-claim-no-completion"}, nil, &out)
		if e != nil || out.String() != "partial-claim-no-completion" {
			return nil, errors.New("cancelled target partial state not proven")
		}
		return map[string]any{"claimPresent": true, "completionAbsent": true}, nil
	}
	e = k.Exec(ctx, h, []string{pvccopy.HelperBinary, "pvc-verify", string(raw)}, nil, &out)
	if e != nil {
		return nil, e
	}
	var marker pvccopy.Marker
	e = json.Unmarshal(out.Bytes(), &marker)
	return marker, e
}
func run(c config) (map[string]any, error) {
	if err := c.validate(); err != nil {
		return nil, err
	}
	p, s, permission, err := compile(c)
	if err != nil {
		return nil, err
	}
	result := map[string]any{"plan": p, "mode": c.Mode, "live": false}
	if c.Mode == "compile" {
		policy, binding, e := pvccopy.FenceManifests(p, c.targetNS(), "copy-runner")
		if e != nil {
			return nil, e
		}
		result["fencePreview"] = []any{policy, binding}
		result["sourceHelperName"] = pvccopy.SourceHelperName(pvccopy.PVCRef{Namespace: s.Namespace, Name: s.Name, UID: s.UID})
		return result, nil
	}
	switch c.Mode {
	case "execute", "cancel", "audit-source", "audit-target", "inspect-partial":
	default:
		return nil, errors.New("invalid driver mode")
	}
	if !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(c.HelperBinarySHA256) {
		return nil, errors.New("matching helper binary SHA256 required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Second)
	defer cancel()
	commands := &commands{c: c, cancel: cancel}
	if e := checkNamespaces(ctx, commands); e != nil {
		return nil, e
	}
	transport := &pvccopy.Kubectl{Commands: commands, RunnerImage: c.Image, ServiceAccount: "default", AllowRootHelpers: true}
	result["live"] = true
	if strings.HasPrefix(c.Mode, "audit") || c.Mode == "inspect-partial" {
		if e := transport.RequireAdmissionFence(ctx, p, c.targetNS(), "copy-runner"); e != nil {
			return nil, e
		}
		value, e := audit(ctx, transport, c, p)
		result["value"] = value
		return result, e
	}
	executor := pvccopy.DomainExecutor{Kubectl: transport, Permission: permission, Sources: []domain.PVCCopySource{s}, Authorize: func(ctx context.Context, p domain.PVCCopyPlan, _ []domain.PVCCopySource) error {
		if e := checkNamespaces(ctx, commands); e != nil {
			return e
		}
		return transport.RequireAdmissionFence(ctx, p, c.targetNS(), "copy-runner")
	}}
	markers, e := executor.ExecuteDomain(ctx, p, []string{c.sourceNS()}, c.Image)
	result["markers"] = markers
	result["interruptedAfterBytes"] = commands.interrupted.Load()
	switch {
	case e == nil:
		result["outcome"] = "complete"
	case errors.Is(e, context.Canceled):
		result["outcome"] = "cancelled"
	case errors.Is(e, pvccopy.ErrPartial):
		result["outcome"] = "partial_target"
	case errors.Is(e, pvccopy.ErrUnsafe):
		result["outcome"] = "unsafe"
	default:
		result["outcome"] = "error"
	}
	// Expected negatives are structured results, not a successful copy marker.
	return result, nil
}
func main() {
	var c config
	decoder := json.NewDecoder(io.LimitReader(os.Stdin, 64<<10))
	decoder.DisallowUnknownFields()
	err := decoder.Decode(&c)
	var result map[string]any
	if err == nil {
		var extra any
		if decoder.Decode(&extra) != io.EOF {
			err = errors.New("trailing configuration")
		}
	}
	if err == nil {
		result, err = run(c)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "fixture driver refused:", err)
		os.Exit(1)
	}
	if err = json.NewEncoder(os.Stdout).Encode(result); err != nil {
		os.Exit(1)
	}
}
