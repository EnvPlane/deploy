package tests

import (
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

var buildControlPlaneDependenciesOnce sync.Once
var controlPlaneChartFixture string

func TestControlPlaneChartDefinesAPIDeploymentAndService(t *testing.T) {
	requiredFiles := []string{
		"../Chart.yaml",
		"../values.yaml",
		"../templates/deployment.yaml",
		"../templates/ingress.yaml",
		"../templates/postgres.yaml",
		"../templates/redis.yaml",
		"../templates/service.yaml",
		"../templates/serviceaccount.yaml",
		"../Chart.lock",
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
		"name: api",
		"range $key, $value := $environment",
		"ENVPILOT_DATABASE_URL",
		"ENVPILOT_REDIS_URL",
		"ENVPILOT_CREDENTIAL_ENCRYPTION_KEY",
		"mountPath: /var/lib/envpilot/data",
	} {
		if !strings.Contains(deploymentText, expected) {
			t.Fatalf("deployment template does not contain %q", expected)
		}
	}

	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values file: %v", err)
	}
	valuesText := string(values)
	for _, expected := range []string{
		"ENVPILOT_ADDR",
		"ENVPLANE_DATA_DIR",
		"ENVPLANE_GITOPS_DIR",
		"ENVPILOT_DATA_DIR",
		"ENVPILOT_GITOPS_DIR",
		"ENVPILOT_POSTGRES_MIGRATIONS_DIR",
		"ENVPILOT_DEPENDENCY_WAIT_TIMEOUT_SECONDS",
		`ENVPILOT_GITHUB_WEBHOOK_DEBUG_PAYLOAD_LOG: "false"`,
		"enabled: false",
		"domain: \"\"",
		"annotations: {}",
		"postgres:",
		"redis:",
		"mode: \"\"",
	} {
		if !strings.Contains(valuesText, expected) {
			t.Fatalf("values file does not contain %q", expected)
		}
	}

	service, err := os.ReadFile("../templates/service.yaml")
	if err != nil {
		t.Fatalf("read service template: %v", err)
	}
	if !strings.Contains(string(service), "kind: Service") {
		t.Fatalf("service template does not contain kind Service")
	}
}

func TestControlPlaneChartManagesCredentialEncryptionKey(t *testing.T) {
	rendered := renderControlPlaneChart(t)
	for _, expected := range []string{
		"name: envpilot-control-plane-runtime-credentials",
		"envpilot.io/purpose: credential-encryption",
		"name: ENVPILOT_CREDENTIAL_ENCRYPTION_KEY",
		"key: \"ENVPILOT_CREDENTIAL_ENCRYPTION_KEY\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("credential encryption contract render missing %q:\n%s", expected, rendered)
		}
	}
}

func TestControlPlaneChartUsesWritableDataAndGitOpsPathsFromEnv(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "env.ENVPLANE_DATA_DIR=/custom/envpilot-data",
		"--set", "env.ENVPLANE_GITOPS_DIR=/custom/envpilot-data/gitops",
	)
	for _, expected := range []string{
		"mountPath: /var/lib/envpilot/data",
		"name: ENVPLANE_DATA_DIR",
		`value: "/custom/envpilot-data"`,
		"name: ENVPLANE_GITOPS_DIR",
		`value: "/custom/envpilot-data/gitops"`,
		"name: ENVPILOT_DATA_DIR",
		`value: "/var/lib/envpilot/data"`,
		"name: ENVPILOT_GITOPS_DIR",
		`value: "/var/lib/envpilot/data/gitops"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("data-path contract render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "/var/lib/envplane") {
		t.Fatalf("control-plane render still references non-writable data path:\n%s", rendered)
	}
}

func TestControlPlaneChartUsesValidGoMemoryLimit(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values file: %v", err)
	}
	if !strings.Contains(string(values), "gomemlimit: 1600MiB") {
		t.Fatalf("default GOMEMLIMIT must use a Go-valid binary suffix: %s", values)
	}
	rendered := renderControlPlaneChart(t)
	if !strings.Contains(rendered, "name: GOMEMLIMIT\n              value: \"1600MiB\"") {
		t.Fatalf("rendered control-plane deployment must set a Go-valid GOMEMLIMIT:\n%s", rendered)
	}
}

func TestControlPlaneChartUsesWriteOnlyOAuthSecretReferences(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "global.envpilot.auth.mode=legacy_secret",
		"--set", "global.envpilot.auth.existingSecret=envpilot-oauth",
		"--set", "auth.gitlab.authURL=https://gitlab.example.test/oauth/authorize",
	)
	for _, expected := range []string{
		"name: ENVPILOT_OAUTH_SESSION_SECRET",
		"name: ENVPILOT_GITLAB_OAUTH_CLIENT_ID",
		"name: ENVPILOT_GITLAB_OAUTH_CLIENT_SECRET",
		"name: \"envpilot-oauth\"",
		"key: oauth-session-secret",
		"key: gitlab-client-id",
		"value: \"https://gitlab.example.test/oauth/authorize\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("OAuth SecretRef contract missing %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{"client-secret:", "oauth-session-secret:", "test-token", "secret-value"} {
		if strings.Contains(rendered, forbidden) && forbidden != "oauth-session-secret:" {
			t.Fatalf("OAuth credential material was rendered: %q\n%s", forbidden, rendered)
		}
	}
	if strings.Contains(rendered, "kind: Secret\nmetadata:\n  name: envpilot-oauth") || strings.Contains(rendered, "kind: Secret\nmetadata:\n  name: \"envpilot-oauth\"") {
		t.Fatalf("OAuth Secret must be operator-managed, not rendered by the chart:\n%s", rendered)
	}
}

func TestControlPlaneChartDisablesOAuthByDefaultAndValidatesLegacyMode(t *testing.T) {
	rendered := renderControlPlaneChart(t)
	for _, forbidden := range []string{
		"ENVPILOT_OAUTH_SESSION_SECRET",
		"ENVPILOT_GITHUB_OAUTH_",
		"ENVPILOT_GITLAB_OAUTH_",
		"ENVPILOT_OIDC_",
		"oauth-session-secret",
	} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("default render unexpectedly contains OAuth configuration %q:\n%s", forbidden, rendered)
		}
	}

	for _, args := range [][]string{
		{"--set", "auth.mode=legacy_secret"},
		{"--set", "auth.github.authURL=https://github.example.test/login/oauth/authorize"},
		{"--set", "auth.existingSecret=envpilot-oauth"},
	} {
		if output := renderControlPlaneChartError(t, args...); !strings.Contains(output, "auth.") {
			t.Fatalf("invalid OAuth mode values did not report auth validation failure:\n%s", output)
		}
	}
}

func TestControlPlaneCanonicalGlobalEnvPlaneOverridesLegacyAuth(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "global.envpilot.auth.mode=legacy_secret",
		"--set", "global.envpilot.auth.existingSecret=legacy-oauth",
		"--set", "global.envplane.auth.mode=disabled",
		"--set", "global.envplane.auth.existingSecret=",
	)
	if strings.Contains(rendered, "name: ENVPILOT_OAUTH_SESSION_SECRET") {
		t.Fatalf("canonical global.envplane auth did not override legacy auth tree:\n%s", rendered)
	}
}

func TestControlPlaneChartPropagatesCanonicalPublicURL(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "global.envpilot.publicURL=https://global.example.test",
		"--set", "publicURL=https://child.example.test",
	)
	if !strings.Contains(rendered, "name: ENVPILOT_PUBLIC_URL\n              value: \"https://child.example.test\"") {
		t.Fatalf("child publicURL must override global publicURL:\n%s", rendered)
	}
}

func TestControlPlaneChartUsesServiceDNSForSameClusterAgentBootstrapAndAllowsRemoteOverride(t *testing.T) {
	sameCluster := renderControlPlaneChart(t, "--namespace", "envpilot")
	for _, expected := range []string{
		"name: ENVPILOT_AGENT_CONTROL_PLANE_URL",
		`value: "http://envpilot-control-plane.envpilot.svc:8080"`,
		"name: ENVPILOT_AGENT_IMAGE_REPOSITORY",
		`value: "ghcr.io/envpilot/agent"`,
		"name: ENVPILOT_AGENT_IMAGE_TAG",
		`value: "0.1.4"`,
	} {
		if !strings.Contains(sameCluster, expected) {
			t.Fatalf("same-cluster bootstrap render missing %q:\n%s", expected, sameCluster)
		}
	}
	remote := renderControlPlaneChart(t,
		"--namespace", "envpilot",
		"--set", "agentBootstrap.controlPlaneURL=https://api.envpilot.example.com",
		"--set", "remoteControlPlane.url=https://remote-control-plane.example.com",
		"--set", "remoteControlPlane.caSecret=remote-control-plane-ca",
		"--set", "remoteControlPlane.clusterID=control-cluster",
		"--set", "agentBootstrap.chart.ref=oci://registry.example/envpilot-agent",
		"--set", "agentBootstrap.chart.version=0.2.7",
	)
	for _, expected := range []string{
		`value: "https://api.envpilot.example.com"`,
		`value: "oci://registry.example/envpilot-agent"`,
		`value: "0.2.7"`,
		`name: ENVPILOT_MANAGEMENT_ENDPOINT_BOOTSTRAP_URL`,
		`value: "https://remote-control-plane.example.com"`,
		`name: ENVPILOT_MANAGEMENT_ENDPOINT_BOOTSTRAP_CA_SECRET`,
		`value: "remote-control-plane-ca"`,
		`name: ENVPILOT_CONTROL_PLANE_CLUSTER_ID`,
		`value: "control-cluster"`,
	} {
		if !strings.Contains(remote, expected) {
			t.Fatalf("remote Agent contract was not rendered %q:\n%s", expected, remote)
		}
	}
	if !strings.Contains(remote, `value: "https://api.envpilot.example.com"`) {
		t.Fatalf("remote Agent endpoint override was not rendered:\n%s", remote)
	}
	umbrellaRemote := renderControlPlaneChart(t,
		"--namespace", "envpilot",
		"--set", "global.envpilot.remoteControlPlane.endpoint=https://api.umbrella.example.com",
		"--set", "global.envpilot.remoteControlPlane.tls.caSecretRef.name=umbrella-remote-ca",
		"--set", "global.envpilot.remoteControlPlane.tls.caSecretRef.key=private-ca.crt",
	)
	for _, expected := range []string{
		`value: "https://api.umbrella.example.com"`,
		`value: "umbrella-remote-ca"`,
		`value: "private-ca.crt"`,
	} {
		if !strings.Contains(umbrellaRemote, expected) {
			t.Fatalf("umbrella remote endpoint contract was not rendered %q:\n%s", expected, umbrellaRemote)
		}
	}
	legacyRemote := renderControlPlaneChart(t,
		"--namespace", "envpilot",
		"--set", "env.ENVPILOT_AGENT_CONTROL_PLANE_URL=https://legacy-api.envpilot.example.com",
	)
	if strings.Count(legacyRemote, "name: ENVPILOT_AGENT_CONTROL_PLANE_URL") != 1 || !strings.Contains(legacyRemote, `value: "https://legacy-api.envpilot.example.com"`) {
		t.Fatalf("legacy remote Agent endpoint must remain supported without duplicate environment variables:\n%s", legacyRemote)
	}
}

func TestControlPlaneChartRendersCommercializationAliasesAndSecretReferences(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "commercialization.billing.provider=stripe",
		"--set", "commercialization.billing.baseURL=https://billing.example.com",
		"--set", "commercialization.billing.apiKeySecretRef.name=envplane-billing",
		"--set", "commercialization.billing.webhookSecretRef.name=envplane-billing",
		"--set", "commercialization.license.graceDays=21",
	)
	for _, expected := range []string{
		"name: ENVPLANE_BILLING_PROVIDER\n              value: \"stripe\"",
		"name: ENVPLANE_BILLING_BASE_URL\n              value: \"https://billing.example.com\"",
		"name: ENVPLANE_BILLING_API_KEY\n              valueFrom:\n                secretKeyRef:\n                  name: \"envplane-billing\"\n                  key: \"api-key\"",
		"name: ENVPLANE_BILLING_WEBHOOK_SECRET\n              valueFrom:\n                secretKeyRef:\n                  name: \"envplane-billing\"\n                  key: \"webhook-secret\"",
		"name: ENVPLANE_LICENSE_GRACE_DAYS\n              value: \"21\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("commercialization deployment contract missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "api-key: ") || strings.Contains(rendered, "webhook-secret: ") {
		t.Fatalf("commercialization secret bytes were rendered instead of SecretRefs:\n%s", rendered)
	}
}

func TestControlPlaneChartUsesNamespaceScopedSecretReaderInsteadOfClusterAdmin(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "rbac.secretReader.enabled=true",
		"--set", "rbac.secretReader.namespaces[0]=envpilot-secrets",
		"--set", "rbac.secretReader.namespaces[1]=shared-secrets",
	)
	for _, expected := range []string{
		"kind: Role",
		"kind: RoleBinding",
		"name: envpilot-control-plane-secret-reader",
		"namespace: \"envpilot-secrets\"",
		"namespace: \"shared-secrets\"",
		"resources: [\"secrets\"]",
		"verbs: [\"get\"]",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("control-plane least-privilege RBAC missing %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{"kind: ClusterRole", "kind: ClusterRoleBinding", "apiGroups: [\"*\"]", "resources: [\"*\"]", "verbs: [\"*\"]"} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("control-plane RBAC retained broad permission %q:\n%s", forbidden, rendered)
		}
	}
}

func TestControlPlaneChartCreatesNameScopedAuthenticationManagedSecret(t *testing.T) {
	for _, test := range []struct {
		name string
		args []string
		secretName string
	}{
		{name: "default", args: []string{"--namespace", "management-system"}, secretName: "envpilot-control-plane-authentication"},
		{name: "override", args: []string{"--namespace", "management-system", "--set", "auth.managedSecret.nameOverride=installation-authentication"}, secretName: "installation-authentication"},
	} {
		t.Run(test.name, func(t *testing.T) {
			rendered := renderControlPlaneChart(t, test.args...)
			for _, expected := range []string{
				"name: " + test.secretName + "\n  namespace: \"management-system\"",
				"envpilot.io/managed-secret: authentication",
				"envpilot.io/purpose: authentication-managed-store",
				"name: envpilot-control-plane-authentication-managed-secret",
				"resourceNames: [\"" + test.secretName + "\"]",
				"verbs: [\"get\", \"update\", \"patch\"]",
				"name: ENVPILOT_AUTHENTICATION_MANAGED_SECRET_NAME\n              value: \"" + test.secretName + "\"",
			} {
				if !strings.Contains(rendered, expected) {
					t.Fatalf("managed authentication Secret contract missing %q:\n%s", expected, rendered)
				}
			}
			for _, occurrence := range []string{
				"name: " + test.secretName + "\n  namespace: \"management-system\"",
				"resourceNames: [\"" + test.secretName + "\"]",
				"value: \"" + test.secretName + "\"",
			} {
				if count := strings.Count(rendered, occurrence); count != 1 {
					t.Fatalf("managed authentication Secret name must occur exactly once as %q; got %d:\n%s", occurrence, count, rendered)
				}
			}
		})
	}

	rendered := renderControlPlaneChart(t, "--namespace", "management-system")
	for _, forbidden := range []string{
		"verbs: [\"get\", \"create\", \"update\", \"patch\"]",
		"verbs: [\"get\", \"update\", \"patch\", \"delete\"]",
		"resourceNames: [\"envpilot-control-plane-authentication\"]\n    verbs: [\"get\", \"list\"]",
	} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("managed authentication Secret RBAC is broader than intended %q:\n%s", forbidden, rendered)
		}
	}

	secretStart := strings.Index(rendered, "name: envpilot-control-plane-authentication\n  namespace: \"management-system\"")
	if secretStart < 0 {
		t.Fatal("managed authentication Secret was not rendered")
	}
	secretEnd := strings.Index(rendered[secretStart:], "\n---")
	secret := rendered[secretStart:]
	if secretEnd >= 0 {
		secret = secret[:secretEnd]
	}
	if strings.Contains(secret, "data:") || strings.Contains(secret, "stringData:") {
		t.Fatalf("managed authentication Secret must be empty:\n%s", secret)
	}
	if output := renderControlPlaneChartError(t, "--set", "auth.managedSecret.nameOverride=not_a_dns_label"); !strings.Contains(output, "auth.managedSecret.nameOverride") {
		t.Fatalf("unsafe managed Secret override was not rejected:\n%s", output)
	}
}

func TestControlPlaneChartUsesPodNamespaceForRemoteClusterLeaderElection(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--namespace", "management-system",
		"--set", "global.envpilot.remoteClusterReconciler.enabled=true",
		"--set", "rbac.remoteClusterReconciler.enabled=true",
	)
	for _, expected := range []string{
		"name: POD_NAMESPACE\n              valueFrom:\n                fieldRef:\n                  fieldPath: metadata.namespace",
		"name: envpilot-control-plane-remote-cluster-reconciler\n  namespace: \"management-system\"",
		"resources: [\"leases\"]",
		"verbs: [\"get\", \"create\", \"update\", \"patch\"]",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("non-default leader-election render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "ENVPILOT_REMOTE_CLUSTER_RECONCILER_NAMESPACE") {
		t.Fatalf("default leader-election contract must derive the namespace from POD_NAMESPACE:\n%s", rendered)
	}
}

func TestControlPlaneChartRendersExplicitLeaderElectionNamespaceAndMatchingRBAC(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--namespace", "management-system",
		"--set", "global.envpilot.remoteClusterReconciler.enabled=true",
		"--set", "rbac.remoteClusterReconciler.enabled=true",
		"--set", "remoteClusterReconciler.leaderElection.namespace=lease-system",
	)
	for _, expected := range []string{
		"name: ENVPILOT_REMOTE_CLUSTER_RECONCILER_NAMESPACE\n              value: \"lease-system\"",
		"name: envpilot-control-plane-remote-cluster-reconciler\n  namespace: \"lease-system\"",
		"name: envpilot-control-plane\n    namespace: management-system",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("explicit leader-election render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Count(rendered, "namespace: \"lease-system\"") < 2 {
		t.Fatalf("explicit leader-election namespace must contain both Role and RoleBinding:\n%s", rendered)
	}
}

func TestControlPlaneChartSupportsExistingServiceAccountAndExternalRBAC(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "serviceAccount.create=false",
		"--set", "serviceAccount.name=platform-api",
		"--set", "rbac.create=false",
	)
	if !strings.Contains(rendered, "serviceAccountName: platform-api") {
		t.Fatalf("existing ServiceAccount was not selected:\n%s", rendered)
	}
	for _, forbidden := range []string{"kind: ServiceAccount", "kind: Role", "kind: RoleBinding"} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("rbac.create=false must not render %s:\n%s", forbidden, rendered)
		}
	}
	chartPath := controlPlaneChartPath(t)
	cmd := exec.Command("helm", "template", "envpilot", chartPath, "--set", "serviceAccount.create=false", "--set", "postgres.auth.existingSecret=chart-test-postgres", "--set", "postgres.tls.enabled=false")
	cmd.Dir = chartPath
	if output, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(output), "serviceAccount.name is required") {
		t.Fatalf("missing existing ServiceAccount name must fail, err=%v output=%s", err, output)
	}
}

func TestControlPlaneDefaultRenderMeetsRestrictedPodSecurityBaseline(t *testing.T) {
	rendered := renderControlPlaneChart(t)
	for _, expected := range []string{
		"runAsNonRoot: true",
		"seccompProfile:",
		"type: RuntimeDefault",
		"allowPrivilegeEscalation: false",
		"drop:",
		"- ALL",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("restricted pod-security baseline missing %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{"privileged: true", "hostNetwork: true", "hostPID: true", "hostIPC: true", "hostPath:"} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("restricted pod-security render contains %q:\n%s", forbidden, rendered)
		}
	}
}

func TestControlPlaneChartRendersIngressForFrontendAndAPIWhenExplicitlyEnabled(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "ingress.enabled=true",
		"--set", "ingress.domain=demo.envpilot.example.com",
		"--set", "ingress.className=nginx",
		"--set", "ingress.certManager.enabled=true",
		"--set", "ingress.certManager.clusterIssuer=letsencrypt-prod",
		"--set", "ingress.tls.enabled=true",
	)
	for _, expected := range []string{
		"kind: Ingress",
		`ingressClassName: nginx`,
		`cert-manager.io/cluster-issuer: "letsencrypt-prod"`,
		`host: "demo.envpilot.example.com"`,
		`- "demo.envpilot.example.com"`,
		`secretName: envpilot-tls`,
		`path: /api`,
		`path: /auth`,
		`path: /webhook`,
		`path: /`,
		"name: envpilot-control-plane-frontend",
		"name: envpilot-control-plane",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart does not contain %q:\n%s", expected, rendered)
		}
	}
}

func TestControlPlaneChartRendersNodePortFrontendWithoutIngress(t *testing.T) {
	rendered := renderControlPlaneChart(t,
		"--set", "ingress.enabled=false",
		"--set", "frontend.service.type=NodePort",
		"--set", "frontend.service.nodePort=31080",
	)
	if strings.Contains(rendered, "kind: Ingress") {
		t.Fatalf("nodeport access must not render an ingress:\n%s", rendered)
	}
	for _, expected := range []string{
		"name: envpilot-control-plane-frontend",
		"type: NodePort",
		"nodePort: 31080",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart missing %q:\n%s", expected, rendered)
		}
	}
}

func TestControlPlaneChartWiresPostgresRedisAndMigrations(t *testing.T) {
	rendered := renderControlPlaneChart(t)
	for _, expected := range []string{
		"kind: StatefulSet",
		"name: envpilot-control-plane-postgres",
		"name: envpilot-control-plane-redis",
		"image: \"postgres:16-alpine\"",
		"image: \"redis:7-alpine\"",
		"name: ENVPILOT_DATABASE_URL",
		"name: ENVPILOT_REDIS_URL",
		"name: wait-postgres",
		"name: wait-redis",
		`value: "redis://:$(REDIS_PASSWORD)@envpilot-control-plane-redis:6379/0"`,
		"--requirepass",
		"envpilot-control-plane-redis-auth",
		`value: "/var/lib/envpilot/migrations/postgres"`,
		"--appendonly",
		"volumeClaimTemplates:",
		"runAsUser: 70",
		"runAsGroup: 70",
		"fsGroup: 70",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("rendered chart does not contain %q:\n%s", expected, rendered)
		}
	}
}

func TestControlPlaneChartUsesPersistentImages(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values file: %v", err)
	}
	valuesText := string(values)
	for _, expected := range []string{
		"repository: ghcr.io/envpilot/api",
		`tag: "0.1.6"`,
	} {
		if !strings.Contains(valuesText, expected) {
			t.Fatalf("values file does not contain %q", expected)
		}
	}
	if strings.Contains(valuesText, "ttl"+".sh") {
		t.Fatalf("values file must not reference temporary image registries")
	}
}

func TestControlPlaneChartUsesCanonicalFrontendDependency(t *testing.T) {
	chart, err := os.ReadFile("../Chart.yaml")
	if err != nil {
		t.Fatalf("read Chart.yaml: %v", err)
	}
	for _, expected := range []string{
		"name: envpilot-frontend",
		"repository: file://../envpilot-frontend",
		"condition: frontend.enabled",
	} {
		if !strings.Contains(string(chart), expected) {
			t.Fatalf("control-plane chart dependency missing %q", expected)
		}
	}
	for _, legacyTemplate := range []string{
		"../templates/frontend-deployment.yaml",
		"../templates/frontend-service.yaml",
	} {
		if _, err := os.Stat(legacyTemplate); !os.IsNotExist(err) {
			t.Fatalf("embedded frontend template %s must be removed", legacyTemplate)
		}
	}
	rendered := renderControlPlaneChart(t)
	for _, expected := range []string{
		"name: envpilot-control-plane-frontend",
		"app.kubernetes.io/name: envpilot-control-plane",
		"app.kubernetes.io/component: frontend",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("legacy frontend upgrade render missing %q:\n%s", expected, rendered)
		}
	}
}

func renderControlPlaneChart(t *testing.T, args ...string) string {
	t.Helper()
	chartPath := controlPlaneChartPath(t)
	commandArgs := append([]string{"template", "envpilot", chartPath, "--set", "postgres.auth.existingSecret=chart-test-postgres", "--set", "postgres.tls.enabled=false"}, args...)
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = chartPath
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	return string(output)
}

func renderControlPlaneChartError(t *testing.T, args ...string) string {
	t.Helper()
	chartPath := controlPlaneChartPath(t)
	commandArgs := append([]string{"template", "envpilot", chartPath, "--set", "postgres.auth.existingSecret=chart-test-postgres", "--set", "postgres.tls.enabled=false"}, args...)
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = chartPath
	output, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("helm template unexpectedly succeeded:\n%s", output)
	}
	return string(output)
}

func controlPlaneChartPath(t *testing.T) string {
	t.Helper()
	buildControlPlaneDependencies(t)
	return controlPlaneChartFixture
}

func buildControlPlaneDependencies(t *testing.T) {
	t.Helper()
	buildControlPlaneDependenciesOnce.Do(func() {
		source, err := filepath.Abs("..")
		if err != nil {
			t.Fatalf("resolve control-plane chart path: %v", err)
		}
		fixtureRoot, err := os.MkdirTemp("", "envpilot-control-plane-chart-")
		if err != nil {
			t.Fatalf("create temporary fixture: %v", err)
		}
		controlPlaneChartFixture = filepath.Join(fixtureRoot, "envpilot-control-plane")
		copyChartTree(t, source, controlPlaneChartFixture)
		copyChartTree(t, filepath.Join(filepath.Dir(source), "envpilot-frontend"), filepath.Join(fixtureRoot, "envpilot-frontend"))
		cmd := exec.Command("helm", "dependency", "build", "--skip-refresh", controlPlaneChartFixture)
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("helm dependency build failed: %v\n%s", err, string(output))
		}
	})
}

func copyChartTree(t *testing.T, source, destination string) {
	t.Helper()
	err := filepath.WalkDir(source, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		target := filepath.Join(destination, relative)
		if entry.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		if !entry.Type().IsRegular() {
			return nil
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		return os.WriteFile(target, contents, info.Mode())
	})
	if err != nil {
		t.Fatalf("copy chart tree: %v", err)
	}
}
