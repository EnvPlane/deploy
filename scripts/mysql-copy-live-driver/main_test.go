package main

import (
	"context"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"io"
	"strings"
	"testing"
)

func TestSpecHashMatchesPython(t *testing.T) {
	b, _ := json.Marshal(map[string]any{"a": "x < 3 && y > 2"})
	h := sha256.Sum256(b)
	if hex.EncodeToString(h[:]) != "0125b84d679852d7e20fc5b882d72dd31db20b2bfa252d5d3acce638ceb9d79d" {
		t.Fatal("spec hash mismatch")
	}
}

func TestCertificateIdentity(t *testing.T) {
	dns := "mysql.mysqlcopy-live-863b4f86af0ae93b-src.svc"
	v, e := certificates(dns)
	if e != nil {
		t.Fatal(e)
	}
	block, _ := pem.Decode([]byte(v["cert"]))
	cert, e := x509.ParseCertificate(block.Bytes)
	if e != nil {
		t.Fatal(e)
	}
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM([]byte(v["ca"]))
	if _, e = cert.Verify(x509.VerifyOptions{DNSName: dns, Roots: roots}); e != nil {
		t.Fatal(e)
	}
	if _, e = cert.Verify(x509.VerifyOptions{DNSName: "mysql.test-app.svc", Roots: roots}); e == nil {
		t.Fatal("foreign name accepted")
	}
	if strings.Contains(v["ca"], "PRIVATE") {
		t.Fatal("public CA includes private key")
	}
	if _, e = certificates("mysql.test-app.svc"); e == nil {
		t.Fatal("foreign fixture accepted")
	}
}
func TestCancellationBoundedPayload(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	k := &commands{cancel: cancel}
	r := &cancelReader{r: strings.NewReader(strings.Repeat("a", 4096)), k: k, remaining: 1024}
	data, e := io.ReadAll(r)
	if e != context.Canceled || len(data) != 1024 || k.transferred != 1024 || ctx.Err() != context.Canceled {
		t.Fatalf("bad bounded cancellation len=%d err=%v", len(data), e)
	}
}
func TestScopeValidationRejectsForeignNamespace(t *testing.T) {
	c := config{RunID: "863b4f86af0ae93b", ClusterUID: "49918e1f-d1f7-4aba-9afb-a4cea4187822", SourceNamespaceUID: "src", TargetNamespaceUID: "dst", Kubeconfig: "fixture", Mode: "positive"}
	c.Plan.Source.PVC.Namespace = "test-app"
	if c.validate() == nil {
		t.Fatal("foreign source accepted")
	}
}
