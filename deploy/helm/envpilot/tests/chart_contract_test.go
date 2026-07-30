package tests

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestInitChartTemplatesInstallerJob(t *testing.T) {
	for _, path := range []string{
		"../Chart.yaml",
		"../values.yaml",
		"../templates/job.yaml",
		"../templates/namespace.yaml",
		"../templates/rbac.yaml",
		"../templates/secret.yaml",
		"../templates/image-pull-secret.yaml",
	} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("required init chart file %s is missing: %v", path, err)
		}
	}

	cmd := exec.Command(
		"helm", "template", "envpilot", "..",
		"--set", "install.clusterId=test-cluster",
		"--set", "registry.token=ghp_test",
		"--set", "storage.className=gp2",
		"--set", "scheduling.nodeArch=arm64",
		"--set", "scheduling.toleration.key=pool",
		"--set", "scheduling.toleration.value=apps",
	)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		"kind: Namespace",
		`name: "envpilot"`,
		`helm.sh/resource-policy: keep`,
		"kind: Job",
		`namespace: "envpilot"`,
		`"helm.sh/hook": post-install,post-upgrade`,
		"kind: ClusterRole",
		`type: kubernetes.io/dockerconfigjson`,
		`name: "envpilot-ghcr"`,
		"ghcr.io/envpilot/install:0.1.10",
		"- -mode",
		`- "clean-install"`,
		"- -cluster-id",
		`- "test-cluster"`,
		"- -deployment-backend",
		`- "helm_direct"`,
		"- -api-image-tag",
		`- "0.1.5"`,
		"- -frontend-image-tag",
		`- "0.1.5"`,
		"- -agent-image-tag",
		`- "0.1.1"`,
		"- -agent-helm-chart-ref",
		`- "oci://ghcr.io/envpilot/envpilot-agent"`,
		"- -agent-helm-chart-version",
		`- "0.1.1"`,
		"- -runner-image-tag",
		`- "0.1.3"`,
		"- -charts-dir",
		`- "/opt/envpilot/helm"`,
		"- -storage-class",
		`- "gp2"`,
		"- -preserve-namespace-cleanup",
		"kubernetes.io/arch: \"arm64\"",
		"key: \"pool\"",
		"ENVPILOT_GHCR_TOKEN",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing %q:\n%s", expected, rendered)
		}
	}
}

func TestInitChartKeepsInstallerNamespaceOnUpgrade(t *testing.T) {
	template, err := os.ReadFile("../templates/namespace.yaml")
	if err != nil {
		t.Fatalf("read namespace template: %v", err)
	}
	text := string(template)
	if strings.Contains(text, "lookup") {
		t.Fatal("namespace template must remain rendered during upgrades so Helm does not delete it")
	}
	if !strings.Contains(text, "helm.sh/resource-policy: keep") {
		t.Fatal("installer namespace must be kept across failed hook upgrades")
	}
}

func TestInitChartSupportsDeploymentBackendSelection(t *testing.T) {
	cmd := exec.Command(
		"helm", "template", "envpilot", "..",
		"--set", "install.clusterId=test-cluster",
		"--set", "registry.token=ghp_test",
		"--set", "deployment.backend=fluxcd",
	)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		"- -deployment-backend",
		`- "fluxcd"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing %q:\n%s", expected, rendered)
		}
	}
}

func TestInitChartSupportsNodePortFrontendAccess(t *testing.T) {
	cmd := exec.Command(
		"helm", "template", "envpilot", "..",
		"--set", "install.clusterId=test-cluster",
		"--set", "registry.token=ghp_test",
		"--set", "access.mode=nodeport",
		"--set", "access.nodePort=31080",
	)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		"- -frontend-access-mode",
		`- "nodeport"`,
		"- -frontend-node-port",
		`- "31080"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing %q:\n%s", expected, rendered)
		}
	}
	notes, err := os.ReadFile("../templates/NOTES.txt")
	if err != nil {
		t.Fatalf("read chart notes: %v", err)
	}
	if !strings.Contains(string(notes), "minikube -p <profile> service") {
		t.Fatal("chart notes must document the supported local NodePort endpoint")
	}
}

func TestInitChartSupportsLegacyCommonImageTagOverride(t *testing.T) {
	cmd := exec.Command(
		"helm", "template", "envpilot", "..",
		"--set", "install.clusterId=test-cluster",
		"--set", "registry.token=ghp_test",
		"--set", "images.tag=0.1.99",
	)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	if strings.Count(rendered, `- "0.1.99"`) != 4 {
		t.Fatalf("legacy images.tag override must apply to every component image tag:\n%s", rendered)
	}
}

func TestInitChartRendersWithLegacyScalarImageValues(t *testing.T) {
	cmd := exec.Command(
		"helm", "template", "envpilot", "..",
		"--set", "install.clusterId=test-cluster",
		"--set", "registry.token=ghp_test",
		"--set-string", "images.api=ghcr.io/envpilot/api",
		"--set-string", "images.frontend=ghcr.io/envpilot/frontend",
		"--set-string", "images.agent=ghcr.io/envpilot/agent",
		"--set-string", "images.runner=ghcr.io/envpilot/runner",
		"--set-string", "images.tag=0.1.0",
	)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("legacy scalar image values must remain upgrade-compatible: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		`- "ghcr.io/envpilot/api"`,
		`- "ghcr.io/envpilot/frontend"`,
		`- "ghcr.io/envpilot/agent"`,
		`- "ghcr.io/envpilot/runner"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered legacy chart missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Count(rendered, `- "0.1.0"`) != 4 {
		t.Fatalf("legacy images.tag must apply to every component tag:\n%s", rendered)
	}
}
