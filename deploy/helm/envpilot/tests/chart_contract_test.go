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
		"ghcr.io/envpilot/install:0.1.16",
		"- -frontend-access-mode",
		`- "ingress"`,
		"- -load-balancer-type",
		`- "nginx"`,
		"- -endpoint-domain",
		`- "local"`,
		"- -mode",
		`- "clean-install"`,
		"- -cluster-id",
		`- "test-cluster"`,
		"- -deployment-backend",
		`- "helm_direct"`,
		"- -api-contract-version",
		`- "1"`,
		"- -api-image-tag",
		`- "0.1.6"`,
		"- -frontend-image-tag",
		`- "0.1.5"`,
		"- -agent-image-tag",
		`- "0.1.4"`,
		"- -agent-helm-chart-ref",
		`- "oci://ghcr.io/envpilot/envpilot-agent"`,
		"- -agent-helm-chart-version",
		`- "0.1.1"`,
		"- -runner-image-tag",
		`- "0.1.4"`,
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

func TestPublishedReleasePinsAPICompatibility(t *testing.T) {
	release, err := os.ReadFile("../../../../release/0.1.16.yaml")
	if err != nil {
		t.Fatalf("read published release manifest: %v", err)
	}
	manifest := string(release)
	for _, expected := range []string{
		`version: "0.1.16"`,
		"apiContract:",
		`version: "1"`,
		"scmOfflineBootstrap: true",
		"api: ghcr.io/envpilot/api:0.1.6",
		"controlPlane: oci://ghcr.io/envpilot/envpilot-control-plane:0.1.6",
		"frontend: ghcr.io/envpilot/frontend:0.1.5",
		"url: http://envpilot.local",
		"ingressClassName: nginx",
		"dockerDriverTunnel: true",
	} {
		if !strings.Contains(manifest, expected) {
			t.Fatalf("release manifest missing compatibility marker %q:\n%s", expected, manifest)
		}
	}
}

func TestLocalEnvironmentFixtureUsesAccessibleSCMDefaultsAndPreflight(t *testing.T) {
	script, err := os.ReadFile("../../../../scripts/minikube-environment-e2e.sh")
	if err != nil {
		t.Fatalf("read local E2E fixture script: %v", err)
	}
	text := string(script)
	for _, expected := range []string{
		`APP_REPOSITORY_URL="${ENVPILOT_E2E_APP_REPOSITORY_URL:-https://gitlab.com/betario/cms-team/cms.git}"`,
		`GITOPS_REPOSITORY_URL="${ENVPILOT_E2E_GITOPS_REPOSITORY_URL:-https://gitlab.com/betario/devops/gitops/fluxcd/clusters.git}"`,
		`.valid == true and .appRepositoryReadable == true and .gitopsRepositoryWritable == true`,
		"SCM preflight failed for provider=",
	} {
		if !strings.Contains(text, expected) {
			t.Fatalf("local E2E fixture missing %q", expected)
		}
	}
}

func TestLocalEnvironmentFixtureUsesCanonicalResourceScanNamespacesField(t *testing.T) {
	script, err := os.ReadFile("../../../../scripts/minikube-environment-e2e.sh")
	if err != nil {
		t.Fatalf("read local E2E fixture script: %v", err)
	}
	text := string(script)
	for _, expected := range []string{
		`selectedBaseNamespaces:[$base]`,
		`resource-scan/start`,
		`resource scan start was not accepted with selectedBaseNamespaces`,
	} {
		if !strings.Contains(text, expected) {
			t.Fatalf("local E2E fixture missing resource-scan contract marker %q", expected)
		}
	}
	if strings.Contains(text, `step_data:{selectedNamespaces:[$base]`) {
		t.Fatal("local E2E fixture must not use deprecated selectedNamespaces for resource scan")
	}
}

func TestLocalEnvironmentFixtureAssertsDeployReadiness(t *testing.T) {
	for path, expected := range map[string][]string{
		"../../../../scripts/minikube-environment-e2e.sh": {
			"assert_deploy_ready()",
			"deployment_readiness.ready",
			"deployment_readiness.missing_prerequisites",
			"Fixture project is deploy-ready",
			`releaseNamePattern:"envpilot-e2e"`,
			`curl -fsS --max-time 2 "http://127.0.0.1:$CHART_PORT/$CHART_ARCHIVE_NAME"`,
			`AGENT_CHART_PORT="${ENVPILOT_E2E_AGENT_CHART_PORT:-18083}"`,
			`ENVPILOT_AGENT_CHART_PORT="$AGENT_CHART_PORT"`,
			"select_fixture_chart_port()",
			"ENVPILOT_E2E_CHART_PORT",
			"Runner Helm chart preflight failed for",
		},
		"../../../../scripts/envpilot-clean-install.sh": {
			"RELEASE_VERSION=\"${ENVPILOT_RELEASE_VERSION:-0.1.16}\"",
			"AGENT_IMAGE_TAG=\"${ENVPILOT_AGENT_IMAGE_TAG:-0.1.4}\"",
			"RUNNER_IMAGE_TAG=\"${ENVPILOT_RUNNER_IMAGE_TAG:-0.1.4}\"",
			"verify_api_capabilities",
			"FRONTEND_ACCESS_MODE=\"${ENVPILOT_FRONTEND_ACCESS_MODE}\"",
			"minikube status -p \"${MINIKUBE_PROFILE}\"",
			"frontend.service.type",
			"start_frontend_access()",
			"Browser UI:",
			"minikube -p ${MINIKUBE_PROFILE} service",
		},
	} {
		script, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read fixture script %s: %v", path, err)
		}
		text := string(script)
		for _, marker := range expected {
			if !strings.Contains(text, marker) {
				t.Fatalf("fixture script %s missing %q", path, marker)
			}
		}
	}
}

func TestInstallersExplicitlyScaleExecutionTargetsUp(t *testing.T) {
	for path, expected := range map[string][]string{
		"../../../../scripts/minikube-environment-e2e.sh": {
			`helm upgrade --install "$AGENT_RELEASE"`,
			`helm upgrade --install "$RUNNER_RELEASE"`,
			"--set replicaCount=1",
			`rollout status "deployment/$AGENT_ID"`,
			`rollout status "deployment/$RUNNER_RELEASE"`,
		},
		"../../../../scripts/envpilot-clean-install.sh": {
			`add_set "replicaCount" "1"`,
			`rollout status "deployment/envpilot-agent"`,
			`rollout status "deployment/envpilot-runner-chart"`,
		},
	} {
		script, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read installer %s: %v", path, err)
		}
		text := string(script)
		for _, marker := range expected {
			if !strings.Contains(text, marker) {
				t.Fatalf("installer %s must ensure an execution target is running; missing %q", path, marker)
			}
		}
	}
}

func TestControlPlaneSuppliesAgentChartReferenceForBootstrapTokens(t *testing.T) {
	values, err := os.ReadFile("../../envpilot-control-plane/values.yaml")
	if err != nil {
		t.Fatalf("read control-plane values: %v", err)
	}
	if !strings.Contains(string(values), "ENVPILOT_AGENT_HELM_CHART_REF: \"oci://ghcr.io/envpilot/envpilot-agent\"") {
		t.Fatal("control-plane chart must configure an Agent chart reference so bootstrap agent-token requests do not return 503")
	}
}

func TestLocalAgentAccessHelperAvoidsStaleChartPortCollisions(t *testing.T) {
	script, err := os.ReadFile("../../../../scripts/minikube-agent-access.sh")
	if err != nil {
		t.Fatalf("read agent access helper: %v", err)
	}
	text := string(script)
	for _, marker := range []string{
		"port_available()",
		"select_chart_port()",
		"ENVPILOT_AGENT_CHART_PORT",
		"Chart server port $CHART_PORT is already in use; using",
		"ENVPILOT_AGENT_CONTROL_PLANE_PORT",
	} {
		if !strings.Contains(text, marker) {
			t.Fatalf("agent access helper missing collision recovery marker %q", marker)
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

func TestInitChartDefaultsToDocumentedLocalIngress(t *testing.T) {
	cmd := exec.Command(
		"helm", "template", "envpilot", "..",
		"--set", "install.clusterId=test-cluster",
		"--set", "registry.token=ghp_test",
	)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		"- -frontend-access-mode",
		`- "ingress"`,
		"- -load-balancer-type",
		`- "nginx"`,
		"- -endpoint-domain",
		`- "local"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing local ingress default %q:\n%s", expected, rendered)
		}
	}
	notes, err := os.ReadFile("../templates/NOTES.txt")
	if err != nil {
		t.Fatalf("read chart notes: %v", err)
	}
	for _, expected := range []string{
		"http://envpilot.{{ .Values.project.endpointDomain }}",
		"minikube -p <profile> addons enable ingress",
		"minikube -p <profile> tunnel",
	} {
		if !strings.Contains(string(notes), expected) {
			t.Fatalf("chart notes must document local ingress marker %q", expected)
		}
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
