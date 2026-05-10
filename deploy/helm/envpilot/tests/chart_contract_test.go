package tests

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestUmbrellaChartDefinesDependenciesAndSecrets(t *testing.T) {
	for _, path := range []string{
		"../Chart.yaml",
		"../values.yaml",
		"../templates/registry-secret.yaml",
		"../templates/bootstrap-secrets.yaml",
	} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("required umbrella chart file %s is missing: %v", path, err)
		}
	}

	chart, err := os.ReadFile("../Chart.yaml")
	if err != nil {
		t.Fatalf("read chart: %v", err)
	}
	for _, expected := range []string{
		"file://../envpilot-control-plane",
		"file://../envpilot-agent",
		"file://../envpilot-runner",
		"alias: controlPlane",
		"alias: agent",
		"alias: runner",
	} {
		if !strings.Contains(string(chart), expected) {
			t.Fatalf("Chart.yaml missing %q", expected)
		}
	}

	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values: %v", err)
	}
	for _, expected := range []string{
		"createPullSecret:",
		"ghcr-envpilot",
		"envpilot-agent-bootstrap",
		"envpilot-runner-bootstrap",
		"ghcr.io/envpilot/api",
		"ghcr.io/envpilot/agent",
		"ghcr.io/envpilot/runner",
	} {
		if !strings.Contains(string(values), expected) {
			t.Fatalf("values.yaml missing %q", expected)
		}
	}
}

func TestUmbrellaChartTemplatesManagedSecrets(t *testing.T) {
	cmd := exec.Command(
		"helm", "template", "envpilot", "..",
		"--set", "registry.createPullSecret=true",
		"--set", "registry.username=envpilot",
		"--set", "registry.password=ghp_test",
		"--set", "bootstrap.agent.createSecret=true",
		"--set", "bootstrap.agent.registrationToken=agent-token",
		"--set", "bootstrap.runner.createSecret=true",
		"--set", "bootstrap.runner.registrationToken=runner-token",
		"--set", "bootstrap.runner.projectConfigToken=config-token",
		"--set", "controlPlane.enabled=false",
		"--set", "agent.enabled=false",
		"--set", "runner.enabled=false",
	)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		"kind: Secret",
		`type: kubernetes.io/dockerconfigjson`,
		`name: "envpilot-agent-bootstrap"`,
		`registration-token: "agent-token"`,
		`name: "envpilot-runner-bootstrap"`,
		`token: "runner-token"`,
		`project-config-token: "config-token"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing %q:\n%s", expected, rendered)
		}
	}
}
