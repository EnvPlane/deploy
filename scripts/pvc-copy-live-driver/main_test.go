package main

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

func fixtureConfig() config {
	return config{RunID: "60a5a5ee57620a88", Context: "kind-envplane-readiness-682", Kubeconfig: "/fixture/kubeconfig", ClusterUID: "cluster-uid", SourceUID: "source-uid", SourceNamespaceUID: "src-ns-uid", TargetNamespaceUID: "dst-ns-uid", SourceName: "source", TargetName: "copy-positive", StorageClass: "standard", Image: "ghcr.io/envplane/runner@sha256:" + strings.Repeat("a", 64), Mode: "compile", HelperBinarySHA256: strings.Repeat("b", 64)}
}
func TestCompileIsOfflineAndFenceIdentitySurvivesTargetChange(t *testing.T) {
	c := fixtureConfig()
	result, e := run(c)
	if e != nil {
		t.Fatal(e)
	}
	requireKey := func(key string) {
		t.Helper()
		if result[key] == nil {
			t.Fatalf("missing %s", key)
		}
	}
	requireKey("plan")
	requireKey("fencePreview")
	requireKey("sourceHelperName")
	if result["live"] != false {
		t.Fatal("compile claimed live execution")
	}
	fence, _ := json.Marshal(result["fencePreview"])
	c.TargetName = "copy-cancel"
	other, e := run(c)
	if e != nil {
		t.Fatal(e)
	}
	otherFence, _ := json.Marshal(other["fencePreview"])
	if string(fence) != string(otherFence) {
		t.Fatal("per-target plan incorrectly changes source onboarding")
	}
	if !strings.Contains(string(fence), c.principal()) || !strings.Contains(string(fence), c.sourceNS()) {
		t.Fatal("scope not bound")
	}
}
func TestUnapprovedScopesAndMutableImagesRefusedWithoutAPI(t *testing.T) {
	for _, change := range []func(*config){
		func(c *config) { c.RunID = "test-app" }, func(c *config) { c.Context = "kind-production" },
		func(c *config) { c.SourceName = "mysql-data" }, func(c *config) { c.TargetName = "existing" },
		func(c *config) { c.Image = "ghcr.io/envplane/runner:latest" }, func(c *config) { c.ClusterUID = "" },
	} {
		c := fixtureConfig()
		change(&c)
		if _, e := run(c); e == nil {
			t.Fatal("invalid fixture accepted")
		}
	}
}
func TestCancellationIsTriggeredOnlyAfterBoundedImportPrefix(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	k := &commands{cancel: cancel}
	reader := &interruptReader{reader: strings.NewReader(strings.Repeat("x", 16000)), ctx: ctx, k: k, remaining: 8192}
	b := make([]byte, 32000)
	n, e := reader.Read(b)
	if n != 8192 || e != nil || ctx.Err() != nil {
		t.Fatal("wrong interruption boundary")
	}
	start := time.Now()
	n, e = reader.Read(b)
	if n != 0 || !errors.Is(e, context.Canceled) || k.interrupted.Load() != 8192 || time.Since(start) > 2*time.Second {
		t.Fatal("cancellation did not stop bounded input")
	}
}
func TestLiveDriverRequiresMatchingBinaryProofBeforeAPI(t *testing.T) {
	c := fixtureConfig()
	c.Mode = "execute"
	c.HelperBinarySHA256 = ""
	if _, e := run(c); e == nil || !strings.Contains(e.Error(), "SHA256 required") {
		t.Fatal("unproved helper execution accepted")
	}
}
