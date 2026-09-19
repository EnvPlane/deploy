package tests

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestFrontendChartRendersStableStandaloneResources(t *testing.T) {
	for _, path := range []string{
		"../Chart.yaml",
		"../values.yaml",
		"../templates/deployment.yaml",
		"../templates/service.yaml",
	} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("required frontend chart file %s is missing: %v", path, err)
		}
	}
	rendered := renderFrontendChart(t, "envplane")
	for _, expected := range []string{
		"kind: Deployment",
		"name: envplane-envplane-frontend",
		"kind: Service",
		`image: "ghcr.io/envplane/frontend:0.1.5"`,
		"app.kubernetes.io/component: frontend",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("frontend chart render missing %q:\n%s", expected, rendered)
		}
	}
}

func TestFrontendChartPreservesLegacyControlPlaneSelector(t *testing.T) {
	rendered := renderFrontendChart(t, "envplane",
		"--set", "fullnameOverride=envplane-control-plane-frontend",
		"--set", "legacyControlPlaneSelector=true",
	)
	for _, expected := range []string{
		"name: envplane-control-plane-frontend",
		"app.kubernetes.io/name: envplane-control-plane",
		"app.kubernetes.io/instance: envplane",
		"app.kubernetes.io/component: frontend",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("legacy frontend render missing %q:\n%s", expected, rendered)
		}
	}
}

func renderFrontendChart(t *testing.T, release string, args ...string) string {
	t.Helper()
	commandArgs := append([]string{"template", release, ".."}, args...)
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	return string(output)
}
