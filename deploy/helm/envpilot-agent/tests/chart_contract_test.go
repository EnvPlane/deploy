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
		"rbac.discovery.scope",
		"rbac.discovery.namespaces",
		"rbac.discovery.readSecrets",
		"resources: [\"namespaces\"]",
		"resources: [\"kustomizations\"]",
		"resources: [\"helmreleases\"]",
		"resources: [\"ingressclasses\"]",
		"resources: [\"customresourcedefinitions\"]",
		"resources: [\"storageclasses\"]",
		"apiGroups: [\"networking.k8s.io\"]",
		"apiGroups: [\"apiextensions.k8s.io\"]",
		"apiGroups: [\"storage.k8s.io\"]",
		"\"get\",\"list\",\"watch\"",
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
		"ENVPILOT_CONTROL_PLANE_CONNECTIVITY_MAX_ATTEMPTS",
		"ENVPILOT_CONTROL_PLANE_CONNECTIVITY_INITIAL_BACKOFF_SECONDS",
		"ENVPILOT_CONTROL_PLANE_CONNECTIVITY_MAX_BACKOFF_SECONDS",
		"ENVPILOT_CONTROL_PLANE_CONNECTIVITY_DEADLINE_SECONDS",
		"ENVPILOT_CLUSTER_ID",
		"ENVPILOT_BOOTSTRAP_PROJECT_ID",
		"ENVPILOT_AGENT_ID",
		"ENVPILOT_AGENT_HEARTBEAT_SECONDS",
		"ENVPILOT_AGENT_AUTH_TOKEN_FILE",
		"ENVPILOT_AGENT_AUTH_TOKEN",
		"ENVPILOT_AGENT_REGISTRATION_TOKEN",
		"ENVPILOT_WATCH_NAMESPACE_SELECTOR",
		"ENVPILOT_WATCH_EXCLUDED_NAMESPACES",
		"volumeMounts:",
		"volumes:",
		"authPersistence",
		"name: control-plane-preflight",
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
		"ENVPILOT_WATCH_EXCLUDED_NAMESPACES",
		"activeDeadlineSeconds",
		"installValidation.timeoutSeconds",
	} {
		if !strings.Contains(installCheckText, expected) {
			t.Fatalf("install validation job template does not contain %q", expected)
		}
	}

}

func TestAgentChartUsesSameClusterDNSAndRequiresRemoteEndpoint(t *testing.T) {
	sameCluster := renderAgentChart(t, "--namespace", "envpilot")
	if !strings.Contains(sameCluster, `value: "http://envpilot-control-plane.envpilot.svc:8080"`) {
		t.Fatalf("same-cluster Agent endpoint must be derived from Service DNS:\n%s", sameCluster)
	}
	remote := renderAgentChart(t,
		"--namespace", "envpilot",
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.url=https://api.remote.example",
		"--set", "controlPlane.tls.caSecret=remote-control-plane-ca",
	)
	if !strings.Contains(remote, `value: "https://api.remote.example"`) ||
		!strings.Contains(remote, `value: "remote"`) ||
		!strings.Contains(remote, "ENVPILOT_CONTROL_PLANE_CA_FILE") ||
		!strings.Contains(remote, `secretName: "remote-control-plane-ca"`) {
		t.Fatalf("remote Agent endpoint override was not rendered:\n%s", remote)
	}
	cmd := exec.Command("helm", "template", "envpilot-agent", "..", "--set", "controlPlane.endpointMode=remote")
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "controlPlane.url is required") {
		 t.Fatalf("remote Agent endpoint without URL must fail, err=%v output=%s", err, output)
	}
	cmd = exec.Command("helm", "template", "envpilot-agent", "..", "--set", "controlPlane.endpointMode=remote", "--set", "controlPlane.url=http://api.remote.example")
	cmd.Dir = "."
	output, err = cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "stable https") {
		t.Fatalf("remote Agent HTTP endpoint must fail, err=%v output=%s", err, output)
	}
	// Older releases may be upgraded with --reuse-values and do not have the
	// nested tls map. The endpoint remains valid when it uses system trust.
	remoteWithoutTLS := renderAgentChart(t,
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.url=https://api.remote.example",
		"--set-json", "controlPlane.tls=null",
	)
	if !strings.Contains(remoteWithoutTLS, `value: "https://api.remote.example"`) ||
		!strings.Contains(remoteWithoutTLS, `value: "remote"`) {
		t.Fatalf("remote Agent endpoint without legacy TLS values was not rendered safely:\n%s", remoteWithoutTLS)
	}
}

func TestAgentChartManagedRemoteUsesOnlyExplicitProjectScopedContract(t *testing.T) {
	rendered := renderAgentChart(t,
		"--set", "managedRemote.enabled=true",
		"--set", "managedRemote.remoteClusterId=target-cluster-a",
		"--set", "managedRemote.projectId=project-a",
		"--set", "managedRemote.authRevision=bootstrap-r2",
		"--set", "managedRemote.authRotation=rotation-20260803",
		"--set", "managedRemote.compatibilityPin=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"--set", "managedRemote.generation=2",
		"--set", "managedRemote.targetNamespaces[0]=project-a-base",
		"--set", "managedRemote.targetNamespaces[1]=project-a-services",
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.url=https://control.example.test",
		"--set", "controlPlane.tls.caSecret=control-plane-ca",
		"--set", "controlPlane.existingSecret=project-a-agent-bootstrap",
		"--set", "rbac.discovery.scope=namespace",
	)
	for _, expected := range []string{
		`envpilot.io/managed-remote: "true"`,
		"envpilot.io/auth-revision: bootstrap-r2",
		`value: "https://control.example.test"`,
		`namespace: "project-a-base"`,
		`namespace: "project-a-services"`,
		`value: "project-a-base,project-a-services"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("managed remote render missing %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{"kind: ClusterRole", "kind: ClusterRoleBinding", "host.minikube.internal"} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("managed remote render must not contain %q:\n%s", forbidden, rendered)
		}
	}

	base := []string{
		"template", "envpilot-agent", "..",
		"--set", "managedRemote.enabled=true",
		"--set", "managedRemote.remoteClusterId=target-cluster-a",
		"--set", "managedRemote.projectId=project-a",
		"--set", "managedRemote.authRevision=bootstrap-r2",
		"--set", "managedRemote.compatibilityPin=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"--set", "managedRemote.generation=2",
		"--set", "managedRemote.targetNamespaces[0]=project-a-base",
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.existingSecret=project-a-agent-bootstrap",
		"--set", "rbac.discovery.scope=namespace",
	}
	for _, invalid := range []struct {
		name string
		url  string
		want string
	}{
		{name: "host local", url: "https://host.minikube.internal:18080", want: "rejects host-local"},
		{name: "foreign service", url: "https://envpilot-control-plane.envpilot.svc.cluster.local:8080", want: "rejects Kubernetes Service DNS"},
	} {
		t.Run(invalid.name, func(t *testing.T) {
			args := append(append([]string{}, base...), "--set", "controlPlane.url="+invalid.url)
			cmd := exec.Command("helm", args...)
			cmd.Dir = "."
			output, err := cmd.CombinedOutput()
			if err == nil || !strings.Contains(string(output), invalid.want) {
				t.Fatalf("managed remote %s URL must fail, err=%v output=%s", invalid.name, err, output)
			}
		})
	}
}

func TestAgentChartGrantsEveryCapabilityScannerRead(t *testing.T) {
	rbac, err := os.ReadFile("../templates/rbac.yaml")
	if err != nil {
		t.Fatalf("read rbac template: %v", err)
	}
	rbacText := string(rbac)

	// API-call-to-RBAC contract: resource_scanner.go and kubernetes.go issue
	// only GET/list/watch calls for these Kubernetes resources. Cluster scope is
	// explicit because namespaces, capability probes and ingress classes are
	// cluster-scoped.
	for _, rule := range []string{
		"resources: [\"namespaces\"]\n    verbs: [\"get\",\"list\",\"watch\"]",
		"- resourcequotas",
		"- limitranges",
		"- persistentvolumeclaims",
		"- serviceaccounts",
		"resources: [\"deployments\",\"daemonsets\",\"replicasets\",\"statefulsets\"]",
		"resources: [\"jobs\",\"cronjobs\"]",
		"resources: [\"ingressclasses\"]",
		"resources: [\"customresourcedefinitions\"]",
		"resources: [\"storageclasses\"]",
		"verbs: [\"get\",\"list\",\"watch\"]",
	} {
		if !strings.Contains(rbacText, rule) {
			t.Fatalf("capability scanner RBAC rule is missing or not read-only:\n%s", rule)
		}
	}
	if strings.Contains(rbacText, "resources: [\"secrets\"]") && !strings.Contains(rbacText, "rbac.discovery.readSecrets") {
		t.Fatalf("Secret API read must remain an explicit opt-in")
	}
}

func TestAgentChartSupportsNamespaceScopedOrExternalRBAC(t *testing.T) {
	namespaceScoped := renderAgentChart(t,
		"--set", "rbac.discovery.scope=namespace",
		"--set", "rbac.discovery.namespaces[0]=team-a",
		"--set", "rbac.discovery.namespaces[1]=team-b",
	)
	for _, expected := range []string{"kind: Role", "kind: RoleBinding", "namespace: \"team-a\"", "namespace: \"team-b\"", `name: ENVPILOT_WATCH_NAMESPACES`, `value: "team-a,team-b"`} {
		if !strings.Contains(namespaceScoped, expected) {
			t.Fatalf("namespace-scoped discovery missing %q:\n%s", expected, namespaceScoped)
		}
	}
	for _, forbidden := range []string{"kind: ClusterRole", "kind: ClusterRoleBinding", "ingressclasses", "customresourcedefinitions", "storageclasses"} {
		if strings.Contains(namespaceScoped, forbidden) {
			t.Fatalf("namespace-scoped discovery must omit cluster RBAC %q:\n%s", forbidden, namespaceScoped)
		}
	}

	projectOwned := renderAgentChart(t,
		"--set", "rbac.discovery.scope=namespace",
		"--set", "rbac.discovery.namespaces[0]=envpilot-executors",
		"--set", "rbac.discovery.clusterCapabilityRead=true",
	)
	for _, expected := range []string{
		"name: envpilot-agent-cluster-capability-reader",
		"kind: ClusterRole",
		"kind: ClusterRoleBinding",
		`resources: ["namespaces"]`,
		`resourceNames:`,
		`- "envpilot-executors"`,
		`verbs: ["get"]`,
		"resources: [\"ingressclasses\"]",
		"resources: [\"customresourcedefinitions\"]",
		"resources: [\"storageclasses\"]",
		"verbs: [\"get\",\"list\",\"watch\"]",
	} {
		if !strings.Contains(projectOwned, expected) {
			t.Fatalf("project-owned capability discovery RBAC missing %q:\n%s", expected, projectOwned)
		}
	}
	for _, forbidden := range []string{"verbs: [\"create\"", "verbs: [\"update\"", "verbs: [\"patch\"", "verbs: [\"delete\"", "resources: [\"namespaces\"]\n    verbs: [\"get\",\"list\",\"watch\"]"} {
		if strings.Contains(projectOwned, forbidden) {
			t.Fatalf("project-owned capability reader must stay minimal/read-only, found %q:\n%s", forbidden, projectOwned)
		}
	}

	external := renderAgentChart(t,
		"--set", "serviceAccount.create=false",
		"--set", "serviceAccount.name=platform-agent",
		"--set", "rbac.create=false",
	)
	if !strings.Contains(external, "serviceAccountName: platform-agent") || strings.Contains(external, "kind: ClusterRole") || strings.Contains(external, "kind: ServiceAccount") {
		t.Fatalf("existing ServiceAccount/external RBAC render is incorrect:\n%s", external)
	}
}

func TestAgentAPIToRBACContractKeepsSecretReadsOptIn(t *testing.T) {
	defaultRender := renderAgentChart(t)
	if strings.Contains(defaultRender, "resources: [\"secrets\"]") {
		t.Fatalf("default Agent RBAC must not read Kubernetes Secrets:\n%s", defaultRender)
	}
	secretRender := renderAgentChart(t, "--set", "rbac.discovery.readSecrets=true")
	for _, expected := range []string{"resources: [\"secrets\"]", "verbs: [\"get\",\"list\",\"watch\"]"} {
		if !strings.Contains(secretRender, expected) {
			t.Fatalf("explicit Secret-discovery RBAC missing %q:\n%s", expected, secretRender)
		}
	}
}

func TestAgentChartRejectsIncompleteDiscoveryOrServiceAccountContracts(t *testing.T) {
	for _, args := range [][]string{
		{"--set", "serviceAccount.create=false"},
	} {
		cmd := exec.Command("helm", append([]string{"template", "envpilot-agent", ".."}, args...)...)
		cmd.Dir = "."
		if output, err := cmd.CombinedOutput(); err == nil {
			t.Fatalf("invalid RBAC values unexpectedly rendered: %v\n%s", args, output)
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
		`tag: "0.1.4"`,
	} {
		if !strings.Contains(valuesText, expected) {
			t.Fatalf("values.yaml does not contain %q", expected)
		}
	}
	if strings.Contains(valuesText, "ttl"+".sh") {
		t.Fatalf("values.yaml must not reference temporary image registries")
	}
}

func TestAgentChartDefaultsToAllNonProtectedNamespaces(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values: %v", err)
	}
	valuesText := string(values)
	for _, expected := range []string{
		`namespaceLabelSelector: ""`,
		"excludeNamespaces:",
		"- default",
		"- kube-system",
		"- envpilot-system",
	} {
		if !strings.Contains(valuesText, expected) {
			t.Fatalf("values.yaml does not contain %q", expected)
		}
	}
	for _, providerSpecific := range []string{"local-path-storage", "ingress-nginx", "kubernetes-dashboard"} {
		if strings.Contains(valuesText, providerSpecific) {
			t.Fatalf("values.yaml must not assume the %q platform namespace", providerSpecific)
		}
	}
}

func TestAgentChartUpgradeChangesCapabilityDiscoveryConfiguration(t *testing.T) {
	render := func(selector string) string {
		t.Helper()
		cmd := exec.Command("helm", "template", "envpilot-agent", "..",
			"--set", "controlPlane.existingSecret=envpilot-agent-bootstrap",
			"--set", "bootstrap.projectId=project-1",
			"--set", "watch.namespaceLabelSelector="+selector,
		)
		cmd.Dir = "."
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("helm template selector %q failed: %v\n%s", selector, err, output)
		}
		return string(output)
	}

	selectorA := render("team=a")
	selectorB := render("team=b")
	if selectorA == selectorB {
		t.Fatal("selector upgrade must change the rendered pod template and restart the agent")
	}
	for _, expected := range []string{`name: ENVPILOT_WATCH_NAMESPACE_SELECTOR`, `value: "team=a"`} {
		if !strings.Contains(selectorA, expected) {
			t.Fatalf("selector A render missing %q:\n%s", expected, selectorA)
		}
	}
	if !strings.Contains(selectorB, `value: "team=b"`) {
		t.Fatalf("selector B render missing updated selector:\n%s", selectorB)
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

func TestAgentChartRendersGenerationScopedAuthPersistenceClaim(t *testing.T) {
	commandArgs := []string{
		"template", "envpilot-agent", "..",
		"--set", "controlPlane.existingSecret=envpilot-agent-bootstrap",
		"--set", "bootstrap.projectId=project-1",
		"--set", "agent.authPersistence.claimName=ep-agent-project-auth-r2",
	}
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	rendered := string(output)
	for _, expected := range []string{
		`name: ep-agent-project-auth-r2`,
		`claimName: "ep-agent-project-auth-r2"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing generation-scoped auth claim %q:\n%s", expected, rendered)
		}
	}
}

func TestAgentChartUsesReleaseAwareResourcesAndSupportsLegacyName(t *testing.T) {
	releaseA := renderAgentChartWithRelease(t, "agent-a", "--set", "controlPlane.existingSecret=agent-a-bootstrap")
	releaseB := renderAgentChartWithRelease(t, "agent-b", "--set", "controlPlane.existingSecret=agent-b-bootstrap")
	for _, expected := range []string{"agent-a-envpilot-agent", "agent-a-envpilot-agent-auth"} {
		if !strings.Contains(releaseA, expected) || strings.Contains(releaseB, expected) {
			t.Fatalf("agent release resources must remain release-aware (%q):\nA=%s\nB=%s", expected, releaseA, releaseB)
		}
	}
	for _, expected := range []string{"agent-b-envpilot-agent", "agent-b-envpilot-agent-auth"} {
		if !strings.Contains(releaseB, expected) || strings.Contains(releaseA, expected) {
			t.Fatalf("agent release resources must remain release-aware (%q):\nA=%s\nB=%s", expected, releaseA, releaseB)
		}
	}

	legacy := renderAgentChartWithRelease(t, "legacy-agent",
		"--set", "fullnameOverride=envpilot-agent",
		"--set", "legacyChartName=envpilot-agent",
		"--set", "controlPlane.existingSecret=legacy-bootstrap",
	)
	for _, expected := range []string{"name: envpilot-agent", "name: envpilot-agent-auth"} {
		if !strings.Contains(legacy, expected) {
			t.Fatalf("legacy agent migration must preserve %q:\n%s", expected, legacy)
		}
	}
}

func renderAgentChart(t *testing.T, args ...string) string {
	t.Helper()
	return renderAgentChartWithRelease(t, "envpilot-agent", args...)
}

func renderAgentChartWithRelease(t *testing.T, releaseName string, args ...string) string {
	t.Helper()
	base := []string{"template", releaseName, "..", "--set", "rbac.discovery.namespaces[0]=default"}
	cmd := exec.Command("helm", append(base, args...)...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, output)
	}
	return string(output)
}
