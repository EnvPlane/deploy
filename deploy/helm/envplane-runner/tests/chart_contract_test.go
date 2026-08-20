package tests

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestRunnerChartDefinesHelmDeployContract(t *testing.T) {
	requiredFiles := []string{
		"../Chart.yaml",
		"../values.yaml",
		"../templates/deployment.yaml",
		"../templates/auth-pvc.yaml",
		"../templates/serviceaccount.yaml",
		"../templates/rbac.yaml",
		"../templates/secret.yaml",
	}
	for _, path := range requiredFiles {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("required chart file %s is missing: %v", path, err)
		}
	}

	deployment, err := os.ReadFile("../templates/deployment.yaml")
	if err != nil {
		t.Fatalf("read deployment template: %v", err)
	}
	deploymentText := string(deployment)
	for _, expected := range []string{
		"kind: Deployment",
		"imagePullSecrets",
		"name: HOME",
		"name: XDG_CACHE_HOME",
		"name: XDG_CONFIG_HOME",
		"name: XDG_DATA_HOME",
		"name: runner-work",
		"ENVPLANE_CONTROL_PLANE_CONNECTIVITY_MAX_ATTEMPTS",
		"ENVPLANE_CONTROL_PLANE_CONNECTIVITY_INITIAL_BACKOFF_SECONDS",
		"ENVPLANE_CONTROL_PLANE_CONNECTIVITY_MAX_BACKOFF_SECONDS",
		"ENVPLANE_CONTROL_PLANE_CONNECTIVITY_DEADLINE_SECONDS",
		"ENVPLANE_CONTROL_PLANE_URL",
		"ENVPLANE_PROJECT_CONFIG_URL",
		"ENVPLANE_PROJECT_CONFIG_TOKEN",
		"ENVPLANE_RUNNER_REGISTRATION_TOKEN",
		"ENVPLANE_RUNNER_AUTH_TOKEN",
		"ENVPLANE_RUNNER_AUTH_TOKEN_FILE",
		"path: /livez",
		"name: control-plane-preflight",
		"/health",
	} {
		if !strings.Contains(deploymentText, expected) {
			t.Fatalf("deployment template does not contain %q", expected)
		}
	}
	rendered := renderRunnerChart(t)
	if strings.Contains(rendered, "\n          args:\n            - runner\n") {
		t.Fatalf("standalone runner image must start without the legacy runner subcommand:\n%s", rendered)
	}
	if !strings.Contains(rendered, "- runner-connectivity-check") {
		t.Fatalf("runner chart must retain the standalone connectivity preflight:\n%s", rendered)
	}
	if !strings.Contains(rendered, "path: /livez") || !strings.Contains(rendered, "readinessProbe:\n            httpGet:\n              path: /health") {
		t.Fatalf("runner chart must keep stale identities live while marking them unready:\n%s", rendered)
	}
	if !strings.Contains(rendered, "startupProbe:\n            httpGet:\n              path: /health") {
		t.Fatalf("runner chart must wait for authenticated startup before startup completion:\n%s", rendered)
	}
	for _, expected := range []string{
		"name: HOME",
		"value: /tmp",
		"name: XDG_CACHE_HOME",
		"value: /tmp/.cache",
		"name: XDG_CONFIG_HOME",
		"value: /tmp/.config",
		"name: XDG_DATA_HOME",
		"value: /tmp/.local/share",
		"mountPath: /tmp",
		"emptyDir: {}",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered runner chart must provide writable Helm workspace %q:\n%s", expected, rendered)
		}
	}

	rbac, err := os.ReadFile("../templates/rbac.yaml")
	if err != nil {
		t.Fatalf("read rbac template: %v", err)
	}
	rbacText := string(rbac)
	for _, expected := range []string{
		"discovery-reader",
		"feature-env-writer",
		"secret-manager",
		"rbac.discovery.scope",
		"rbac.featureEnvWriter.mode",
		"releaseNamespace",
		"preconfiguredNamespaces",
		"generatedFeatureNamespaces",
		"rbac.featureEnvWriter.namespaces",
		"rbac.featureEnvWriter.generatedNamespaces",
		"rbac.featureEnvWriter.allowNetworkPolicies",
		"rbac.featureEnvWriter.allowFluxResources",
		"rbac.featureEnvWriter.helmReleaseStorage",
		"rbac.secretManager.enabled",
	} {
		if !strings.Contains(rbacText, expected) {
			t.Fatalf("rbac template does not contain %q", expected)
		}
	}
}

func TestRunnerChartUsesSameClusterDNSAndRequiresRemoteEndpoint(t *testing.T) {
	sameCluster := renderRunnerChart(t, "--namespace", "envplane")
	if !strings.Contains(sameCluster, `value: "http://envplane-control-plane.envplane.svc:8080"`) {
		t.Fatalf("same-cluster Runner endpoint must be derived from Service DNS:\n%s", sameCluster)
	}
	remote := renderRunnerChart(t,
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.url=https://api.remote.example",
		"--set", "controlPlane.tls.caSecret=remote-control-plane-ca",
	)
	if !strings.Contains(remote, `value: "https://api.remote.example"`) ||
		!strings.Contains(remote, `value: "remote"`) ||
		!strings.Contains(remote, "ENVPLANE_CONTROL_PLANE_CA_FILE") ||
		!strings.Contains(remote, `secretName: "remote-control-plane-ca"`) {
		t.Fatalf("remote Runner endpoint override was not rendered:\n%s", remote)
	}
	// Releases created before the TLS block was added must remain upgradeable
	// with --reuse-values. A remote endpoint does not require a private CA.
	// Deliberately set the historical value to nil: the template must not use a
	// dotted lookup that dereferences the missing map.
	remoteWithoutTLS := renderRunnerChart(t,
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.url=https://api.remote.example",
		"--set-json", "controlPlane.tls=null",
	)
	if !strings.Contains(remoteWithoutTLS, `value: "https://api.remote.example"`) ||
		strings.Contains(remoteWithoutTLS, "ENVPLANE_CONTROL_PLANE_CA_FILE") {
		t.Fatalf("remote Runner endpoint without legacy TLS values was not rendered safely:\n%s", remoteWithoutTLS)
	}
	deployment, err := os.ReadFile("../templates/deployment.yaml")
	if err != nil {
		t.Fatalf("read deployment template: %v", err)
	}
	if !strings.Contains(string(deployment), `get $controlPlane "tls"`) ||
		strings.Contains(string(deployment), ".Values.controlPlane.tls") {
		t.Fatal("deployment template must safely access an optional legacy controlPlane.tls map")
	}
	cmd := exec.Command("helm", "template", "envplane-runner", "..", "--set", "controlPlane.endpointMode=remote")
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "controlPlane.url is required") {
		t.Fatalf("remote Runner endpoint without URL must fail, err=%v output=%s", err, output)
	}
	cmd = exec.Command("helm", "template", "envplane-runner", "..", "--set", "controlPlane.endpointMode=remote", "--set", "controlPlane.url=http://api.remote.example")
	cmd.Dir = "."
	output, err = cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "stable https") {
		t.Fatalf("remote Runner HTTP endpoint must fail, err=%v output=%s", err, output)
	}
}

func TestRunnerChartManagedRemoteUsesProjectScopedWriterRBAC(t *testing.T) {
	rendered := renderRunnerChart(t,
		"--set", "managedRemote.enabled=true",
		"--set", "managedRemote.remoteClusterId=target-cluster-a",
		"--set", "managedRemote.projectId=project-a",
		"--set", "managedRemote.authRevision=bootstrap-r2",
		"--set", "managedRemote.authRotation=rotation-20260803",
		"--set", "managedRemote.compatibilityPin=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"--set", "managedRemote.generation=2",
		"--set", "managedRemote.targetNamespaces[0]=project-a-pr-1",
		"--set", "managedRemote.targetNamespaces[1]=project-a-pr-2",
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.url=https://control.example.test",
		"--set", "controlPlane.tls.caSecret=control-plane-ca",
		"--set", "controlPlane.existingSecret=project-a-runner-bootstrap",
		"--set", "rbac.discovery.scope=namespace",
		"--set", "rbac.discovery.namespace=project-a-system",
		"--set", "rbac.featureEnvWriter.mode=preconfiguredNamespaces",
		"--set", "rbac.featureEnvWriter.namespaces[0]=project-a-pr-1",
		"--set", "rbac.featureEnvWriter.namespaces[1]=project-a-pr-2",
	)
	for _, expected := range []string{
		`envplane.io/managed-remote: "true"`,
		"envplane.io/auth-revision: bootstrap-r2",
		`value: "https://control.example.test"`,
		"namespace: project-a-pr-1",
		"namespace: project-a-pr-2",
		"resources:\n      - secrets",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("managed remote runner render missing %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{"kind: ClusterRole", "kind: ClusterRoleBinding", "host.minikube.internal"} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("managed remote runner render must not contain %q:\n%s", forbidden, rendered)
		}
	}

	base := []string{
		"template", "envplane-runner", "..",
		"--set", "managedRemote.enabled=true",
		"--set", "managedRemote.remoteClusterId=target-cluster-a",
		"--set", "managedRemote.projectId=project-a",
		"--set", "managedRemote.authRevision=bootstrap-r2",
		"--set", "managedRemote.compatibilityPin=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"--set", "managedRemote.generation=2",
		"--set", "managedRemote.targetNamespaces[0]=project-a-pr-1",
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.existingSecret=project-a-runner-bootstrap",
		"--set", "rbac.discovery.scope=namespace",
		"--set", "rbac.discovery.namespace=project-a-system",
		"--set", "rbac.featureEnvWriter.mode=preconfiguredNamespaces",
		"--set", "rbac.featureEnvWriter.namespaces[0]=project-a-pr-1",
	}
	for _, invalid := range []struct {
		name string
		url  string
		want string
	}{
		{name: "host local", url: "https://host.minikube.internal:18080", want: "rejects host-local"},
		{name: "foreign service", url: "https://envplane-control-plane.envplane.svc.cluster.local:8080", want: "rejects Kubernetes Service DNS"},
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

func TestRunnerChartManagedRemoteWithoutConcreteFeatureNamespaceDoesNotGrantWriterRBAC(t *testing.T) {
	rendered := renderRunnerChart(t,
		"--set", "managedRemote.enabled=true",
		"--set", "managedRemote.remoteClusterId=target-cluster-a",
		"--set", "managedRemote.projectId=project-a",
		"--set", "managedRemote.authRevision=bootstrap-r2",
		"--set", "managedRemote.compatibilityPin=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"--set", "managedRemote.generation=2",
		"--set", "controlPlane.endpointMode=remote",
		"--set", "controlPlane.url=https://control.example.test",
		"--set", "controlPlane.existingSecret=project-a-runner-bootstrap",
		"--set", "rbac.discovery.scope=namespace",
		"--set", "rbac.discovery.namespace=project-a-system",
		"--set", "rbac.featureEnvWriter.enabled=false",
		"--set", "rbac.featureEnvWriter.mode=preconfiguredNamespaces",
	)
	if strings.Contains(rendered, "feature-env-writer") || strings.Contains(rendered, "resources:\n      - secrets") {
		t.Fatalf("a remote Runner with no concrete feature namespace must not receive broad Helm Secret RBAC:\n%s", rendered)
	}
}

func TestRunnerChartUsesPersistentImage(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values: %v", err)
	}
	valuesText := string(values)
	for _, expected := range []string{
		"repository: ghcr.io/envplane/runner",
		`tag: "0.2.0"`,
	} {
		if !strings.Contains(valuesText, expected) {
			t.Fatalf("values.yaml does not contain %q", expected)
		}
	}
	if strings.Contains(valuesText, "ttl"+".sh") {
		t.Fatalf("values.yaml must not reference temporary image registries")
	}
}

func TestRunnerChartDocumentsAuthPersistenceSecret(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values: %v", err)
	}
	valuesText := string(values)
	for _, expected := range []string{
		"authPersistence:",
		"runner-auth-token",
		"existingSecret:",
		"runnerAuthTokenKey:",
		"runnerAuthToken",
		"one-time bootstrap token",
		"createClaim:",
		"claimName:",
	} {
		if !strings.Contains(valuesText, expected) {
			t.Fatalf("values.yaml does not document auth persistence field %q", expected)
		}
	}

	rendered := renderRunnerChart(
		t,
		"--set", "controlPlane.authPersistence.existingSecret=envplane-runner-auth",
	)
	if !strings.Contains(rendered, "ENVPLANE_RUNNER_AUTH_TOKEN") {
		t.Fatalf("rendered chart missing persisted runner auth token env:\n%s", rendered)
	}
	if !strings.Contains(rendered, "name: \"envplane-runner-auth\"") {
		t.Fatalf("rendered chart missing persisted auth secret reference:\n%s", rendered)
	}
	if !strings.Contains(rendered, "key: \"runner-auth-token\"") {
		t.Fatalf("rendered chart missing persisted auth secret key:\n%s", rendered)
	}
	if !strings.Contains(rendered, "ENVPLANE_RUNNER_AUTH_TOKEN_FILE") {
		t.Fatalf("rendered chart missing persisted runner auth token file:\n%s", rendered)
	}
	if !strings.Contains(rendered, "kind: PersistentVolumeClaim") {
		t.Fatalf("rendered chart missing default auth persistence PVC:\n%s", rendered)
	}
	if !strings.Contains(rendered, "claimName: \"envplane-runner-auth\"") {
		t.Fatalf("rendered chart missing auth PVC claim reference:\n%s", rendered)
	}
}

func TestRunnerChartMountsPrivateOCIRegistryCredentialsForHelmPreflight(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values: %v", err)
	}
	for _, expected := range []string{"helmRegistry:", "configKey:", "mountPath:", "only authenticate Kubernetes image pulls"} {
		if !strings.Contains(string(values), expected) {
			t.Fatalf("values.yaml must document private Helm registry configuration %q", expected)
		}
	}
	rendered := renderRunnerChart(t,
		"--set", "helmRegistry.existingSecret=private-oci-auth",
		"--set", "helmRegistry.configKey=.dockerconfigjson",
	)
	for _, expected := range []string{
		"name: HELM_REGISTRY_CONFIG",
		"value: \"/var/run/envplane/helm-registry/config.json\"",
		"name: helm-registry-config",
		"secretName: \"private-oci-auth\"",
		"key: \".dockerconfigjson\"",
		"path: config.json",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("private OCI registry preflight configuration missing %q:\n%s", expected, rendered)
		}
	}
}

func TestRunnerChartDefaultRBACIsLeastPrivilege(t *testing.T) {
	rendered := renderRunnerChart(t)
	docs := renderedDocs(rendered)
	if !strings.Contains(rendered, "kind: ClusterRole") {
		t.Fatalf("default chart should render read-only discovery ClusterRole")
	}
	if !strings.Contains(rendered, "discovery-reader") {
		t.Fatalf("default chart should render discovery-reader RBAC")
	}
	if !strings.Contains(rendered, "feature-env-writer") {
		t.Fatalf("default chart should render feature-env-writer RBAC")
	}
	if strings.Contains(rendered, "secret-manager") {
		t.Fatalf("secret-manager RBAC must be disabled by default")
	}

	for _, doc := range docs {
		if !docIsKind(doc, "ClusterRole") {
			continue
		}
		for _, forbiddenVerb := range []string{`"create"`, `"update"`, `"patch"`, `"delete"`} {
			if strings.Contains(doc, forbiddenVerb) {
				t.Fatalf("default ClusterRole must not include write verb %s:\n%s", forbiddenVerb, doc)
			}
		}
		if docHasAnyResource(doc, "secrets") && docHasAnyVerb(doc, `"create"`, `"update"`, `"patch"`, `"delete"`) {
			t.Fatalf("default chart must not grant cluster-wide secret writes:\n%s", doc)
		}
		if docHasAnyResource(doc, "deployments", "statefulsets", "replicasets", "daemonsets") &&
			docHasAnyVerb(doc, `"delete"`) {
			t.Fatalf("default chart must not grant cluster-wide workload delete:\n%s", doc)
		}
	}

	writerDoc := findDoc(docs, "kind: Role", "feature-env-writer")
	if writerDoc == "" {
		t.Fatalf("feature-env-writer Role not found")
	}
	if !docHasAnyResource(writerDoc, "secrets") || !docHasAnyVerb(writerDoc, `"create"`, `"delete"`) {
		t.Fatalf("feature-env-writer must manage namespace-scoped Helm release secrets:\n%s", writerDoc)
	}
	if docHasAnyResource(writerDoc, "networkpolicies", "helmreleases", "kustomizations", "gitrepositories") {
		t.Fatalf("feature-env-writer optional capabilities must be disabled by default:\n%s", writerDoc)
	}
}

func TestRunnerChartSupportsExistingServiceAccountAndExternalRBAC(t *testing.T) {
	rendered := renderRunnerChart(t,
		"--set", "serviceAccount.create=false",
		"--set", "serviceAccount.name=platform-runner",
		"--set", "rbac.create=false",
	)
	if !strings.Contains(rendered, "serviceAccountName: platform-runner") {
		t.Fatalf("existing ServiceAccount was not selected:\n%s", rendered)
	}
	for _, forbidden := range []string{"kind: ServiceAccount", "kind: Role", "kind: RoleBinding", "kind: ClusterRole", "kind: ClusterRoleBinding"} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("rbac.create=false must not render %s:\n%s", forbidden, rendered)
		}
	}
	cmd := exec.Command("helm", "template", "envplane-runner", "..", "--set", "serviceAccount.create=false")
	cmd.Dir = "."
	if output, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(output), "serviceAccount.name is required") {
		t.Fatalf("missing existing ServiceAccount name must fail, err=%v output=%s", err, output)
	}
}

func TestRunnerChartPreconfiguredNamespaceWriterRendersPerNamespace(t *testing.T) {
	rendered := renderRunnerChart(
		t,
		"--set", "rbac.featureEnvWriter.mode=preconfiguredNamespaces",
		"--set", "rbac.featureEnvWriter.namespaces[0]=envplane-pr-123",
		"--set", "rbac.featureEnvWriter.namespaces[1]=envplane-pr-124",
	)
	docs := renderedDocs(rendered)
	for _, namespace := range []string{"envplane-pr-123", "envplane-pr-124"} {
		if role := findResourceDoc(docs, "Role", "envplane-runner-feature-env-writer", namespace); role == "" {
			t.Fatalf("feature-env-writer Role not found in namespace %s:\n%s", namespace, rendered)
		}
		binding := findResourceDoc(docs, "RoleBinding", "envplane-runner-feature-env-writer", namespace)
		if binding == "" {
			t.Fatalf("feature-env-writer RoleBinding not found in namespace %s:\n%s", namespace, rendered)
		}
		if !strings.Contains(binding, "namespace: envplane-system") {
			t.Fatalf("feature namespace writer RoleBinding must bind the release service account:\n%s", binding)
		}
	}
	if role := findResourceDoc(docs, "Role", "envplane-runner-feature-env-writer", "envplane-system"); role != "" {
		t.Fatalf("preconfigured namespace mode must not also render release-namespace writer Role:\n%s", role)
	}
}

func TestRunnerChartGeneratedFeatureNamespaceWriterRendersPerNamespace(t *testing.T) {
	rendered := renderRunnerChart(
		t,
		"--set", "rbac.featureEnvWriter.mode=generatedFeatureNamespaces",
		"--set", "rbac.featureEnvWriter.generatedNamespaces[0]=envplane-pr-201",
	)
	docs := renderedDocs(rendered)
	if role := findResourceDoc(docs, "Role", "envplane-runner-feature-env-writer", "envplane-pr-201"); role == "" {
		t.Fatalf("generated feature namespace writer Role not found:\n%s", rendered)
	}
	if binding := findResourceDoc(docs, "RoleBinding", "envplane-runner-feature-env-writer", "envplane-pr-201"); binding == "" {
		t.Fatalf("generated feature namespace writer RoleBinding not found:\n%s", rendered)
	}
	deployment := findResourceDoc(docs, "Deployment", "envplane-runner", "")
	for _, expected := range []string{"ENVPLANE_FEATURE_ENV_WRITER_MODE", "generatedFeatureNamespaces", "ENVPLANE_FEATURE_ENV_WRITER_NAMESPACES", "envplane-pr-201"} {
		if !strings.Contains(deployment, expected) {
			t.Fatalf("runner deployment must report its rendered target namespace RBAC contract (%q):\n%s", expected, deployment)
		}
	}
}

func TestRunnerChartNamespaceScopedDiscoveryUsesRoleBinding(t *testing.T) {
	rendered := renderRunnerChart(t, "--set", "rbac.discovery.scope=namespace")
	if strings.Contains(rendered, "kind: ClusterRoleBinding") {
		t.Fatalf("namespace-scoped discovery must not render ClusterRoleBinding:\n%s", rendered)
	}
	if strings.Contains(rendered, "kind: ClusterRole") {
		t.Fatalf("namespace-scoped discovery must not render ClusterRole:\n%s", rendered)
	}
	discoveryRole := findDoc(renderedDocs(rendered), "kind: Role", "discovery-reader")
	if discoveryRole == "" {
		t.Fatalf("namespace-scoped discovery Role not found:\n%s", rendered)
	}
	if !strings.Contains(rendered, "kind: RoleBinding") {
		t.Fatalf("namespace-scoped discovery RoleBinding not found:\n%s", rendered)
	}
}

func TestRunnerChartCapabilityFlagsControlOptionalPermissions(t *testing.T) {
	rendered := renderRunnerChart(
		t,
		"--set", "rbac.featureEnvWriter.allowNetworkPolicies=true",
		"--set", "rbac.featureEnvWriter.allowFluxResources=true",
		"--set", "rbac.secretManager.enabled=true",
	)
	docs := renderedDocs(rendered)
	writerDoc := findDoc(docs, "kind: Role", "feature-env-writer")
	if writerDoc == "" {
		t.Fatalf("feature-env-writer Role not found")
	}
	for _, expectedResource := range []string{
		"networkpolicies",
		"helmreleases",
		"kustomizations",
		"gitrepositories",
	} {
		if !docHasAnyResource(writerDoc, expectedResource) {
			t.Fatalf("enabled feature-env-writer capability missing %s:\n%s", expectedResource, writerDoc)
		}
	}

	secretManagerDoc := findDoc(docs, "kind: Role", "secret-manager")
	if secretManagerDoc == "" {
		t.Fatalf("secret-manager Role not found when enabled")
	}
	if !docHasAnyResource(secretManagerDoc, "secrets") {
		t.Fatalf("secret-manager must manage secrets when enabled:\n%s", secretManagerDoc)
	}
	for _, doc := range docs {
		if docIsKind(doc, "ClusterRole") && docHasAnyResource(doc, "secrets") &&
			docHasAnyVerb(doc, `"create"`, `"update"`, `"patch"`, `"delete"`) {
			t.Fatalf("secret-manager must remain namespace-scoped, found cluster-wide secret write:\n%s", doc)
		}
	}
}

func TestRunnerChartSecretManagerUsesExplicitNamespaceAllowlist(t *testing.T) {
	rendered := renderRunnerChart(t,
		"--set", "rbac.secretManager.enabled=true",
		"--set", "rbac.secretManager.namespaces[0]=feature-a",
		"--set", "rbac.secretManager.namespaces[1]=feature-b",
	)
	docs := renderedDocs(rendered)
	for _, namespace := range []string{"feature-a", "feature-b"} {
		if role := findResourceDoc(docs, "Role", "envplane-runner-secret-manager", namespace); role == "" {
			t.Fatalf("secret-manager Role not found in exact namespace %s", namespace)
		}
	}
	for _, doc := range docs {
		if docIsKind(doc, "ClusterRole") && strings.Contains(doc, "secret-manager") {
			t.Fatalf("secret materialization must not grant cluster-wide RBAC:\n%s", doc)
		}
	}
}

func TestRunnerChartRejectsPlaintextBootstrapTokensWithoutExplicitOverride(t *testing.T) {
	commandArgs := []string{
		"template", "envplane-runner", "..",
		"--namespace", "envplane-system",
		"--set", "controlPlane.token=raw-runner-token",
		"--set", "controlPlane.configToken=raw-config-token",
	}
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("helm template should fail when plaintext tokens are set without override:\n%s", string(output))
	}
	if !strings.Contains(string(output), "allowUnsafePlaintextTokens=true") {
		t.Fatalf("expected unsafe plaintext token guidance, got:\n%s", string(output))
	}
}

func TestRunnerChartAllowsPlaintextBootstrapTokensOnlyWithExplicitOverride(t *testing.T) {
	rendered := renderRunnerChart(
		t,
		"--set", "controlPlane.token=raw-runner-token",
		"--set", "controlPlane.configToken=raw-config-token",
		"--set", "controlPlane.allowUnsafePlaintextTokens=true",
	)
	if !strings.Contains(rendered, "raw-runner-token") || !strings.Contains(rendered, "raw-config-token") {
		t.Fatalf("explicit unsafe override should render tokens for local testing:\n%s", rendered)
	}
}

func TestRunnerChartRendersIndependentResourcesForTwoReleases(t *testing.T) {
	unsafeBootstrapTokens := []string{
		"--set", "controlPlane.allowUnsafePlaintextTokens=true",
		"--set", "controlPlane.token=registration-token",
		"--set", "controlPlane.configToken=config-token",
	}
	releaseA := renderRunnerChartWithRelease(t, "runner-a", unsafeBootstrapTokens...)
	releaseB := renderRunnerChartWithRelease(t, "runner-b", unsafeBootstrapTokens...)
	resourcesA := renderedResourceKeys(releaseA)
	resourcesB := renderedResourceKeys(releaseB)
	if len(resourcesA) == 0 || len(resourcesB) == 0 {
		t.Fatalf("expected both releases to render Kubernetes resources")
	}
	for resource := range resourcesA {
		if _, collision := resourcesB[resource]; collision {
			t.Fatalf("runner releases must not render colliding resources: %s", resource)
		}
	}
	for _, expected := range []string{
		"runner-a-envplane-runner",
		"runner-a-envplane-runner-auth",
		"runner-a-envplane-runner-token",
		"runner-a-envplane-runner-discovery-reader",
		"runner-a-envplane-runner-feature-env-writer",
	} {
		if !strings.Contains(releaseA, expected) {
			t.Fatalf("runner-a render missing release-aware resource %q:\n%s", expected, releaseA)
		}
	}
	for _, expected := range []string{
		"runner-b-envplane-runner",
		"runner-b-envplane-runner-auth",
		"runner-b-envplane-runner-token",
		"runner-b-envplane-runner-discovery-reader",
		"runner-b-envplane-runner-feature-env-writer",
	} {
		if !strings.Contains(releaseB, expected) {
			t.Fatalf("runner-b render missing release-aware resource %q:\n%s", expected, releaseB)
		}
	}
}

func TestRunnerChartLegacyFullnameOverridePreservesExistingAuthPVC(t *testing.T) {
	legacy := renderRunnerChartWithRelease(t, "envplane-runner",
		"--set", "fullnameOverride=envplane-runner-chart",
		"--set", "legacyChartName=envplane-runner-chart",
	)
	docs := renderedDocs(legacy)
	for _, kind := range []string{"Deployment", "ServiceAccount"} {
		if resource := findResourceDoc(docs, kind, "envplane-runner-chart", ""); resource == "" {
			t.Fatalf("legacy fullname override must preserve %s name:\n%s", kind, legacy)
		}
	}
	if pvc := findResourceDoc(docs, "PersistentVolumeClaim", "envplane-runner-chart-auth", ""); pvc == "" {
		t.Fatalf("legacy fullname override must preserve existing auth PVC:\n%s", legacy)
	}
	notes, err := os.ReadFile("../templates/NOTES.txt")
	if err != nil {
		t.Fatalf("read chart notes: %v", err)
	}
	if !strings.Contains(string(notes), "fullnameOverride=envplane-runner-chart") ||
		!strings.Contains(string(notes), "legacyChartName=envplane-runner-chart") {
		t.Fatalf("chart notes must document the legacy fullname migration")
	}
}

func renderRunnerChart(t *testing.T, args ...string) string {
	t.Helper()
	return renderRunnerChartWithRelease(t, "envplane-runner", args...)
}

func renderRunnerChartWithRelease(t *testing.T, releaseName string, args ...string) string {
	t.Helper()
	commandArgs := append([]string{"template", releaseName, "..", "--namespace", "envplane-system"}, args...)
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	return string(output)
}

func renderedResourceKeys(rendered string) map[string]struct{} {
	resources := make(map[string]struct{})
	for _, doc := range renderedDocs(rendered) {
		kind := ""
		name := ""
		lines := strings.Split(doc, "\n")
		for _, line := range lines {
			if strings.HasPrefix(line, "kind: ") {
				kind = strings.TrimSpace(strings.TrimPrefix(line, "kind: "))
			}
		}
		for index, line := range lines {
			if line != "metadata:" || index+1 >= len(lines) {
				continue
			}
			for _, metadataLine := range lines[index+1:] {
				if !strings.HasPrefix(metadataLine, "  ") {
					break
				}
				if strings.HasPrefix(metadataLine, "  name: ") {
					name = strings.Trim(strings.TrimSpace(strings.TrimPrefix(metadataLine, "  name: ")), `"`)
					break
				}
			}
			break
		}
		if kind != "" && name != "" {
			resources[kind+"/"+name] = struct{}{}
		}
	}
	return resources
}

func renderedDocs(rendered string) []string {
	rawDocs := strings.Split(rendered, "\n---")
	docs := make([]string, 0, len(rawDocs))
	for _, raw := range rawDocs {
		doc := strings.TrimSpace(raw)
		if doc != "" {
			docs = append(docs, doc)
		}
	}
	return docs
}

func findDoc(docs []string, needles ...string) string {
	for _, doc := range docs {
		matches := true
		for _, needle := range needles {
			if !strings.Contains(doc, needle) {
				matches = false
				break
			}
		}
		if matches {
			return doc
		}
	}
	return ""
}

func findResourceDoc(docs []string, kind string, name string, namespace string) string {
	for _, doc := range docs {
		if !docIsKind(doc, kind) {
			continue
		}
		if !strings.Contains(doc, "\n  name: "+name+"\n") && !strings.Contains(doc, "\n  name: "+name+"\r\n") {
			continue
		}
		if namespace != "" && !strings.Contains(doc, "\n  namespace: "+namespace+"\n") && !strings.Contains(doc, "\n  namespace: "+namespace+"\r\n") {
			continue
		}
		return doc
	}
	return ""
}

func docIsKind(doc string, kind string) bool {
	return strings.Contains(doc, "\nkind: "+kind+"\n") || strings.HasPrefix(doc, "kind: "+kind+"\n")
}

func docHasAnyResource(doc string, resources ...string) bool {
	for _, resource := range resources {
		if strings.Contains(doc, "- "+resource) {
			return true
		}
	}
	return false
}

func docHasAnyVerb(doc string, verbs ...string) bool {
	for _, verb := range verbs {
		if strings.Contains(doc, verb) {
			return true
		}
	}
	return false
}
