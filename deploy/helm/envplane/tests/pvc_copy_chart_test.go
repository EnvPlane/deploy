package tests

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

func TestRunnerPVCCopyIsOptInAndSourceExecutionIsExactNamed(t *testing.T) {
	ordinary := renderChildChart(t, "envplane-runner")
	if strings.Contains(ordinary, "ENVPLANE_PVC_COPY_HELPER_IMAGE") || strings.Contains(ordinary, "pvc-copy-fence-reader") {
		t.Fatal("default chart expands copy access")
	}
	rendered := renderChildChart(t, "envplane-runner", "--set", "pvcCopy.enabled=true", "--set", "image.digest=sha256:"+strings.Repeat("a", 64), "--set", "pvcCopy.sources[0].namespace=base", "--set", "pvcCopy.sources[0].name=data", "--set", "pvcCopy.sources[0].uid=source-uid", "--set", "pvcCopy.fenceNames[0]=exact-fence")
	hash := sha256.Sum256([]byte("base/data/source-uid"))
	helper := "pvccopy-source-" + hex.EncodeToString(hash[:12])
	for _, expected := range []string{"ENVPLANE_PVC_COPY_SOURCE_NAMESPACES", "spec.serviceAccountName", helper, "resources: [\"pods/exec\"]", "resourceNames: [\"" + helper + "\"]", "resourceNames: [\"data\"]", "validatingadmissionpolicies", "exact-fence"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("copy profile missing %q", expected)
		}
	}
	// Source exec/delete are separate named rules. No source Secret read/write,
	// source PVC mutation, policy install or RBAC mutation is generated.
	roleStart := strings.Index(rendered, "namespace: \"base\"")
	if roleStart < 0 {
		t.Fatal("source role missing")
	}
	role := strings.Split(rendered[roleStart:], "---")[0]
	if strings.Contains(role, "secrets") || strings.Contains(role, "update") || strings.Contains(role, "patch") {
		t.Fatalf("source privileges widened: %s", role)
	}
}
