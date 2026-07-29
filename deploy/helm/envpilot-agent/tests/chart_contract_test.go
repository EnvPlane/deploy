package tests

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestAgentChartDefinesHelmInstallAndRBACContract(t *testing.T) {
	requiredFiles := []string{
		"../Chart.yaml",
		"../values.yaml",
		"../templates/deployment.yaml",
		"../templates/auth-pvc.yaml",
		"../templates/install-validation-job.yaml",
		"../templates/serviceaccount.yaml",
		"../templates/rbac.yaml",
		"../templates/ttl-cleanup-cronjob.yaml",
	}
	for _, path := range requiredFiles {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("required chart file %s is missing: %v", path, err)
		}
	}

	rbac, err := os.ReadFile("../templates/rbac.yaml")
	if err != nil {
		t.Fatalf("read rbac template: %v", err)
	}
	rbacText := string(rbac)
	for _, expected := range []string{
		"kind: ClusterRole",
		"kind: ClusterRoleBinding",
		"- namespaces",
		"- kustomizations",
		"- helmreleases",
		"- get",
		"- list",
		"- watch",
	} {
		if !strings.Contains(rbacText, expected) {
			t.Fatalf("rbac template does not contain %q", expected)
		}
	}
	for _, forbidden := range []string{"- create", "- update", "- patch", "- delete"} {
		if strings.Contains(rbacText, forbidden) {
			t.Fatalf("rbac template must stay read-only, found %q", forbidden)
		}
	}

	deployment, err := os.ReadFile("../templates/deployment.yaml")
	if err != nil {
		t.Fatalf("read deployment template: %v", err)
	}
	deploymentText := string(deployment)
	for _, expected := range []string{
		"kind: Deployment",
		"serviceAccountName:",
		"ENVPILOT_CONTROL_PLANE_URL",
		"ENVPILOT_CLUSTER_ID",
		"ENVPILOT_BOOTSTRAP_PROJECT_ID",
		"ENVPILOT_AGENT_ID",
		"ENVPILOT_AGENT_HEARTBEAT_SECONDS",
		"ENVPILOT_AGENT_AUTH_TOKEN_FILE",
		"ENVPILOT_AGENT_AUTH_TOKEN",
		"ENVPILOT_AGENT_REGISTRATION_TOKEN",
		"volumeMounts:",
		"volumes:",
		"authPersistence",
		"name: wait-control-plane",
	} {
		if !strings.Contains(deploymentText, expected) {
			t.Fatalf("deployment template does not contain %q", expected)
		}
	}
	if strings.Contains(deploymentText, "ENVPILOT_AGENT_TOKEN") {
		t.Fatalf("deployment template must not contain legacy ENVPILOT_AGENT_TOKEN")
	}

	installCheck, err := os.ReadFile("../templates/install-validation-job.yaml")
	if err != nil {
		t.Fatalf("read install validation job template: %v", err)
	}
	installCheckText := string(installCheck)
	for _, expected := range []string{
		"helm.sh/hook\": test",
		"kind: Job",
		"agent-install-check",
		"ENVPILOT_CLUSTER_ID",
		"ENVPILOT_CONTROL_PLANE_URL",
		"activeDeadlineSeconds",
		"installValidation.timeoutSeconds",
	} {
		if !strings.Contains(installCheckText, expected) {
			t.Fatalf("install validation job template does not contain %q", expected)
		}
	}

	cronJob, err := os.ReadFile("../templates/ttl-cleanup-cronjob.yaml")
	if err != nil {
		t.Fatalf("read ttl cleanup cronjob template: %v", err)
	}
	cronJobText := string(cronJob)
	for _, expected := range []string{
		"kind: CronJob",
		"ttl-cleanup",
		"ENVPILOT_CONTROL_PLANE_URL",
		"ENVPILOT_TTL_CLEANUP_TIMEOUT_SECONDS",
		"ENVPILOT_AGENT_REGISTRATION_TOKEN",
	} {
		if !strings.Contains(cronJobText, expected) {
			t.Fatalf("ttl cleanup cronjob template does not contain %q", expected)
		}
	}
}

func TestAgentChartUsesPersistentImage(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values: %v", err)
	}
	valuesText := string(values)
	for _, expected := range []string{
		"repository: ghcr.io/envpilot/agent",
		`tag: "0.1.0"`,
	} {
		if !strings.Contains(valuesText, expected) {
			t.Fatalf("values.yaml does not contain %q", expected)
		}
	}
	if strings.Contains(valuesText, "ttl"+".sh") {
		t.Fatalf("values.yaml must not reference temporary image registries")
	}
}

func TestAgentChartRejectsPlaintextBootstrapTokenWithoutExplicitOverride(t *testing.T) {
	commandArgs := []string{"template", "envpilot-agent", "..", "--set", "controlPlane.token=raw-agent-token"}
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("helm template should fail when plaintext token is set without override:\n%s", string(output))
	}
	if !strings.Contains(string(output), "allowUnsafePlaintextTokens=true") {
		t.Fatalf("expected unsafe plaintext token guidance, got:\n%s", string(output))
	}
}

func TestAgentChartAllowsPlaintextBootstrapTokenOnlyWithExplicitOverride(t *testing.T) {
	commandArgs := []string{
		"template", "envpilot-agent", "..",
		"--set", "controlPlane.token=raw-agent-token",
		"--set", "controlPlane.allowUnsafePlaintextTokens=true",
	}
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed with explicit unsafe override: %v\n%s", err, string(output))
	}
	if !strings.Contains(string(output), "raw-agent-token") {
		t.Fatalf("explicit unsafe override should render token for local testing:\n%s", string(output))
	}
}

func TestAgentChartRendersAuthTokenPersistenceEnvAndVolume(t *testing.T) {
	commandArgs := []string{
		"template", "envpilot-agent", "..",
		"--set", "controlPlane.existingSecret=envpilot-agent-bootstrap",
		"--set", "bootstrap.projectId=project-1",
		"--set", "agent.authPersistence.existingClaim=envpilot-agent-auth",
		"--set", "agent.authPersistence.existingSecret=envpilot-agent-auth-secret",
	}
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		"name: ENVPILOT_AGENT_AUTH_TOKEN_FILE",
		`value: "/var/lib/envpilot-agent/auth/agent-auth-token"`,
		`mountPath: "/var/lib/envpilot-agent/auth"`,
		`claimName: "envpilot-agent-auth"`,
		`name: "envpilot-agent-auth-secret"`,
		`key: "agent-auth-token"`,
		"fsGroup: 65532",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing %q:\n%s", expected, rendered)
		}
	}
}

func TestAgentChartRendersDefaultAuthPersistencePVC(t *testing.T) {
	commandArgs := []string{
		"template", "envpilot-agent", "..",
		"--set", "controlPlane.existingSecret=envpilot-agent-bootstrap",
		"--set", "bootstrap.projectId=project-1",
		"--set", "agent.authPersistence.storageClassName=gp2",
	}
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		"kind: PersistentVolumeClaim",
		`name: envpilot-agent-auth`,
		`storageClassName: "gp2"`,
		`claimName: "envpilot-agent-auth"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing %q:\n%s", expected, rendered)
		}
	}
}
