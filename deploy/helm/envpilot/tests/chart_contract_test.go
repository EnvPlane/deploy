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
		`name: "envpilot-installer"`,
		"kind: Job",
		`namespace: "envpilot-installer"`,
		"kind: ClusterRole",
		`type: kubernetes.io/dockerconfigjson`,
		`name: "envpilot-ghcr"`,
		"ghcr.io/envpilot/install:0.1.0",
		"- -mode",
		`- "clean-install"`,
		"- -cluster-id",
		`- "test-cluster"`,
		"- -charts-dir",
		`- "/opt/envpilot/helm"`,
		"- -storage-class",
		`- "gp2"`,
		"kubernetes.io/arch: \"arm64\"",
		"key: \"pool\"",
		"ENVPILOT_GHCR_TOKEN",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing %q:\n%s", expected, rendered)
		}
	}
}
