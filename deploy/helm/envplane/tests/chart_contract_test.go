package tests

import (
	"encoding/json"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

var buildUmbrellaDependencies sync.Once
var umbrellaChartFixture string

func withFixturePostgres(values []string) []string {
	base := []string{
		"--set", "envplane-control-plane.postgres.auth.password=test-fixture-password",
		"--set", "envplane-control-plane.postgres.tls.enabled=false",
		"--set", "access.ingress.allowInsecureHttp=true",
	}
	return append(values, base...)
}

func withChildFixturePostgres(values []string) []string {
	return append(values,
		"--set", "postgres.auth.password=test-fixture-password",
		"--set", "postgres.tls.enabled=false",
	)
}

func buildDependencies(t *testing.T) {
	t.Helper()
	buildUmbrellaDependencies.Do(func() {
		source, err := filepath.Abs("..")
		if err != nil {
			t.Fatalf("resolve source chart path: %v", err)
		}
		fixtureRoot, err := os.MkdirTemp("", "envplane-umbrella-chart-")
		if err != nil {
			t.Fatalf("create temporary fixture: %v", err)
		}
		umbrellaChartFixture = filepath.Join(fixtureRoot, "envplane")
		copyChartTree(t, source, umbrellaChartFixture)
		for _, dependency := range []string{
			"envplane-control-plane",
			"envplane-frontend",
			"envplane-agent",
			"envplane-runner",
			"envplane-webhook",
			"envplane-e2e-workload",
		} {
			dependencySource := filepath.Join(filepath.Dir(source), dependency)
			if _, err := os.Stat(dependencySource); err == nil {
				copyChartTree(t, dependencySource, filepath.Join(fixtureRoot, dependency))
			}
		}
		cmd := exec.Command("helm", "dependency", "build", "--skip-refresh", umbrellaChartFixture)
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("build umbrella dependencies: %v\n%s", err, output)
		}
	})
}

func umbrellaChartPath(t *testing.T) string {
	t.Helper()
	buildDependencies(t)
	return umbrellaChartFixture
}

func renderUmbrella(t *testing.T, values ...string) string {
	t.Helper()
	chartPath := umbrellaChartPath(t)
	args := append([]string{"template", "envplane", chartPath, "--namespace", "envplane",
		"--set", "envplane-control-plane.postgres.auth.password=test-fixture-password",
		"--set", "envplane-control-plane.postgres.tls.enabled=false",
		"--set", "access.ingress.allowInsecureHttp=true",
	}, values...)
	cmd := exec.Command("helm", args...)
	cmd.Dir = chartPath
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, output)
	}
	return string(output)
}

func renderUmbrellaError(t *testing.T, values ...string) string {
	t.Helper()
	chartPath := umbrellaChartPath(t)
	args := append([]string{"template", "envplane", chartPath, "--namespace", "envplane",
		"--set", "envplane-control-plane.postgres.auth.password=test-fixture-password",
		"--set", "envplane-control-plane.postgres.tls.enabled=false",
		"--set", "access.ingress.allowInsecureHttp=true",
	}, values...)
	cmd := exec.Command("helm", args...)
	cmd.Dir = chartPath
	output, err := cmd.CombinedOutput()
	if err == nil {
		t.Fatalf("helm template unexpectedly succeeded:\n%s", output)
	}
	return string(output)
}

func TestUmbrellaAuthenticationModeDefaultsToDisabled(t *testing.T) {
	rendered := renderUmbrella(t)
	for _, forbidden := range []string{
		"ENVPLANE_OAUTH_SESSION_SECRET",
		"ENVPLANE_GITHUB_OAUTH_",
		"ENVPLANE_GITLAB_OAUTH_",
		"ENVPLANE_OIDC_",
		"oauth-session-secret",
	} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("default umbrella render unexpectedly contains OAuth configuration %q:\n%s", forbidden, rendered)
		}
	}

	legacy := renderUmbrella(t,
		"--set", "global.envplane.auth.mode=legacy_secret",
		"--set", "global.envplane.auth.existingSecret=envplane-oauth",
		"--set", "envplane-control-plane.auth.gitlab.authURL=https://gitlab.example.test/oauth/authorize",
	)
	for _, expected := range []string{
		"name: ENVPLANE_OAUTH_SESSION_SECRET",
		"name: ENVPLANE_GITLAB_OAUTH_CLIENT_ID",
		"key: oauth-session-secret",
		`value: "https://gitlab.example.test/oauth/authorize"`,
	} {
		if !strings.Contains(legacy, expected) {
			t.Fatalf("legacy umbrella render missing %q:\n%s", expected, legacy)
		}
	}

	for _, values := range [][]string{
		{"--set", "global.envplane.auth.mode=legacy_secret"},
		{"--set", "global.envplane.auth.existingSecret=envplane-oauth"},
		{"--set", "envplane-control-plane.auth.github.authURL=https://github.example.test/login/oauth/authorize"},
	} {
		if output := renderUmbrellaError(t, values...); !strings.Contains(output, "auth") {
			t.Fatalf("invalid umbrella authentication values did not report validation failure:\n%s", output)
		}
	}
}

func TestCanonicalGlobalEnvPlaneValuesOverrideLegacyTree(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "global.envplane.auth.mode=legacy_secret",
		"--set", "global.envplane.auth.existingSecret=legacy-oauth",
		"--set", "global.envplane.auth.mode=disabled",
		"--set", "global.envplane.auth.existingSecret=",
		"--set", "global.envplane.bootstrapDefaults.helmDirect.chartVersion=9.9.9",
	)
	if strings.Contains(rendered, "name: ENVPLANE_OAUTH_SESSION_SECRET") {
		t.Fatalf("canonical global.envplane auth did not override legacy auth tree:\n%s", rendered)
	}
	if !strings.Contains(rendered, "9.9.9") {
		t.Fatalf("canonical global.envplane bootstrap default was not propagated:\n%s", rendered)
	}
}

func TestUmbrellaPassesActivationVerificationKeysToControlPlane(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set-string", "envplane-control-plane.commercialization.license.activationPublicKeysJSON=test-issuer-key",
	)
	for _, expected := range []string{
		"name: ENVPLANE_ACTIVATION_PUBLIC_KEYS_JSON",
		"test-issuer-key",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("canonical activation verification key was not rendered %q:\n%s", expected, rendered)
		}
	}
}

// Render one canonical child chart in an isolated chart tree. Published
// umbrellas intentionally reject runtime image overrides that conflict with
// their signed compatibility manifest, but the child charts must still support
// the explicit repository/tag/digest contract for independent installation.
// Copying the control-plane's frontend dependency alongside it keeps this test
// self-contained and avoids writing generated archives into the source tree.
func renderChildChart(t *testing.T, chartName string, values ...string) string {
	t.Helper()
	sourceRoot, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatalf("resolve canonical chart root: %v", err)
	}
	temporaryRoot := t.TempDir()
	chartPath := filepath.Join(temporaryRoot, chartName)
	copyChartTree(t, filepath.Join(sourceRoot, chartName), chartPath)
	if chartName == "envplane-control-plane" {
		copyChartTree(t, filepath.Join(sourceRoot, "envplane-frontend"), filepath.Join(temporaryRoot, "envplane-frontend"))
	}

	dependencies := exec.Command("helm", "dependency", "build", "--skip-refresh", chartPath)
	output, err := dependencies.CombinedOutput()
	if err != nil {
		t.Fatalf("build %s child dependencies: %v\n%s", chartName, err, output)
	}
	args := append([]string{"template", "envplane", chartPath, "--namespace", "envplane"}, withChildFixturePostgres(values)...)
	cmd := exec.Command("helm", args...)
	output, err = cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("render %s child chart: %v\n%s", chartName, err, output)
	}
	return string(output)
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

func renderPublishedUmbrella(t *testing.T, values ...string) (string, error) {
	t.Helper()
	buildDependencies(t)
	sourceChart, err := filepath.Abs("..")
	if err != nil {
		t.Fatalf("resolve source chart: %v", err)
	}
	temporaryChart := filepath.Join(t.TempDir(), "envplane")
	copyChartTree(t, sourceChart, temporaryChart)
	for _, dependency := range []string{
		"envplane-control-plane",
		"envplane-frontend",
		"envplane-agent",
		"envplane-runner",
		"envplane-webhook",
		"envplane-e2e-workload",
	} {
		copyChartTree(t, filepath.Join(filepath.Dir(sourceChart), dependency), filepath.Join(filepath.Dir(temporaryChart), dependency))
	}
	dependencies := exec.Command("helm", "dependency", "build", "--skip-refresh", temporaryChart)
	if output, err := dependencies.CombinedOutput(); err != nil {
		t.Fatalf("build published umbrella test dependencies: %v\n%s", err, output)
	}
	manifestPath := filepath.Join(temporaryChart, "compatibility", "release.json")
	if err := os.MkdirAll(filepath.Dir(manifestPath), 0o755); err != nil {
		t.Fatalf("create compatibility directory: %v", err)
	}
	generator, err := filepath.Abs("../../../../scripts/generate-umbrella-compatibility-manifest.sh")
	if err != nil {
		t.Fatalf("resolve compatibility generator: %v", err)
	}
	cmd := exec.Command(generator,
		"--version", umbrellaChartVersion(t),
		"--source-revision", strings.Repeat("0", 40),
		"--values-file", filepath.Join(sourceChart, "values.yaml"),
		"--chart-file", filepath.Join(sourceChart, "Chart.yaml"),
		"--output", manifestPath,
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("generate test compatibility manifest: %v\n%s", err, output)
	}

	args := append([]string{"template", "envplane", temporaryChart, "--namespace", "envplane"}, withFixturePostgres(values)...)
	cmd = exec.Command("helm", args...)
	output, err = cmd.CombinedOutput()
	return string(output), err
}

func umbrellaChartVersion(t *testing.T) string {
	t.Helper()
	chart, err := os.ReadFile("../Chart.yaml")
	if err != nil {
		t.Fatalf("read Chart.yaml: %v", err)
	}
	for _, line := range strings.Split(string(chart), "\n") {
		if version, found := strings.CutPrefix(line, "version: "); found && strings.TrimSpace(version) != "" {
			return strings.TrimSpace(version)
		}
	}
	t.Fatal("umbrella Chart.yaml has no version")
	return ""
}

func TestUmbrellaUsesDirectCanonicalDependencies(t *testing.T) {
	chart, err := os.ReadFile("../Chart.yaml")
	if err != nil {
		t.Fatalf("read Chart.yaml: %v", err)
	}
	for _, expected := range []string{
		"apiVersion: v2",
		"name: envplane",
		"name: envplane-control-plane",
		"name: envplane-frontend",
		"name: envplane-agent",
		"name: envplane-runner",
		"name: envplane-webhook",
		"name: envplane-e2e-workload",
		"condition: controlPlane.enabled",
		"condition: frontend.enabled",
		"condition: agent.enabled",
		"condition: runner.enabled",
		"condition: webhook.enabled",
		"condition: e2eWorkload.enabled",
	} {
		if !strings.Contains(string(chart), expected) {
			t.Fatalf("umbrella Chart.yaml missing %q:\n%s", expected, chart)
		}
	}

	for _, retired := range []string{
		"../templates/job.yaml",
		"../templates/namespace.yaml",
		"../templates/rbac.yaml",
		"../templates/serviceaccount.yaml",
		"../templates/secret.yaml",
		"../templates/image-pull-secret.yaml",
		"../../../../Dockerfile",
		"../../../../cmd/envplane-install",
	} {
		if _, err := os.Stat(retired); !os.IsNotExist(err) {
			t.Fatalf("retired installer template must not exist: %s", retired)
		}
	}
	for _, workflow := range []string{
		"../../../../.github/workflows/publish-main.yaml",
		"../../../../.github/workflows/publish-umbrella.yaml",
	} {
		contents, err := os.ReadFile(workflow)
		if err != nil {
			t.Fatalf("read workflow %s: %v", workflow, err)
		}
		if strings.Contains(string(contents), "ghcr.io/${{ github.repository_owner }}/install") ||
			strings.Contains(string(contents), "docker/build-push-action") {
			t.Fatalf("workflow %s still publishes the retired installer image", workflow)
		}
	}
}

func TestUmbrellaInjectsDefaultHelmDirectBootstrapChartWithoutInstallingIt(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values: %v", err)
	}
	for _, expected := range []string{
		"bootstrapDefaults:",
		"chartRef: oci://ghcr.io/envplane/envplane-e2e-workload",
		`chartVersion: "0.1.0"`,
		"e2eWorkload:",
		"enabled: false",
	} {
		if !strings.Contains(string(values), expected) {
			t.Fatalf("umbrella values missing %q:\n%s", expected, values)
		}
	}
	rendered := renderUmbrella(t)
	for _, expected := range []string{
		"name: ENVPLANE_BOOTSTRAP_DEFAULT_HELM_DIRECT_CHART_REF",
		`value: "oci://ghcr.io/envplane/envplane-e2e-workload"`,
		"name: ENVPLANE_BOOTSTRAP_DEFAULT_HELM_DIRECT_CHART_VERSION",
		`value: "0.1.0"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("active umbrella render missing Helm Direct bootstrap default %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "envplane-e2e-workload/templates/") {
		t.Fatalf("disabled Helm Direct bootstrap chart must not render as an umbrella workload:\n%s", rendered)
	}
}

func TestUmbrellaInjectsReleaseCompatibleAgentChartContract(t *testing.T) {
	chart, err := os.ReadFile("../Chart.yaml")
	if err != nil {
		t.Fatalf("read Chart.yaml: %v", err)
	}
	agentVersion := ""
	inAgentDependency := false
	for _, line := range strings.Split(string(chart), "\n") {
		if line == "  - name: envplane-agent" {
			inAgentDependency = true
			continue
		}
		if inAgentDependency && strings.HasPrefix(line, "  - name: ") {
			break
		}
		if inAgentDependency {
			if value, ok := strings.CutPrefix(line, "    version: "); ok {
				agentVersion = strings.TrimSpace(value)
				break
			}
		}
	}
	if agentVersion == "" {
		t.Fatal("envplane-agent dependency version is missing")
	}
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values.yaml: %v", err)
	}
	if !strings.Contains(string(values), `ref: "oci://ghcr.io/envplane/envplane-agent"`) || !strings.Contains(string(values), `version: "`+agentVersion+`"`) {
		t.Fatalf("umbrella values must carry the release-compatible Agent chart contract for %s:\n%s", agentVersion, values)
	}
	rendered := renderUmbrella(t)
	for _, expected := range []string{
		`name: ENVPLANE_AGENT_HELM_CHART_REF`,
		`value: "oci://ghcr.io/envplane/envplane-agent"`,
		`name: ENVPLANE_AGENT_HELM_CHART_VERSION`,
		`value: "` + agentVersion + `"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("active umbrella render missing Agent chart contract %q:\n%s", expected, rendered)
		}
	}
}

func TestUmbrellaForwardsControlPlaneWritableEnvPathsToChild(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "envplane-control-plane.env.ENVPLANE_DATA_DIR=/custom/umbrella/data",
		"--set", "envplane-control-plane.env.ENVPLANE_GITOPS_DIR=/custom/umbrella/data/gitops",
	)
	for _, expected := range []string{
		"# Source: envplane/charts/envplane-control-plane/templates/deployment.yaml",
		"mountPath: /var/lib/envplane/data",
		"name: ENVPLANE_DATA_DIR",
		`value: "/custom/umbrella/data"`,
		"name: ENVPLANE_GITOPS_DIR",
		`value: "/custom/umbrella/data/gitops"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("umbrella control-plane env-path contract missing %q:\n%s", expected, rendered)
		}
	}
}

func TestUmbrellaDefinesPrivateOrPublicHTTPSRemoteControlPlaneContract(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "global.envplane.managementEndpointProfile.bootstrap.endpoint=https://envplane.platform.internal",
		"--set", "global.envplane.managementEndpointProfile.bootstrap.tls.serverName=envplane.platform.internal",
		"--set", "global.envplane.managementEndpointProfile.bootstrap.tls.caSecretRef.name=envplane-remote-ca",
		"--set", "global.envplane.managementEndpointProfile.bootstrap.tls.caSecretRef.key=private-ca.crt",
	)
	for _, expected := range []string{
		"name: ENVPLANE_MANAGEMENT_ENDPOINT_BOOTSTRAP_URL",
		`value: "https://envplane.platform.internal"`,
		"name: ENVPLANE_MANAGEMENT_ENDPOINT_BOOTSTRAP_TLS_SERVER_NAME",
		"name: ENVPLANE_MANAGEMENT_ENDPOINT_BOOTSTRAP_CA_SECRET",
		`value: "envplane-remote-ca"`,
		`value: "private-ca.crt"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("private-or-public remote endpoint render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "BEGIN CERTIFICATE") {
		t.Fatalf("remote endpoint render must reference CA Secrets, never include certificate data:\n%s", rendered)
	}

	buildDependencies(t)
	chartPath := umbrellaChartPath(t)
	for name, args := range map[string][]string{
		"host-local":       {"--set", "global.envplane.remoteControlPlane.endpoint=https://envplane.local"},
		"insecure-ingress": {"--set", "access.mode=ingress", "--set", "access.ingress.host=api.envplane.example.test", "--set", "global.envplane.remoteControlPlane.endpoint=https://api.envplane.example.test"},
	} {
		cmd := exec.Command("helm", append([]string{"template", "envplane", chartPath}, withFixturePostgres(args)...)...)
		cmd.Dir = chartPath
		output, err := cmd.CombinedOutput()
		if err == nil {
			t.Fatalf("%s remote endpoint contract must fail:\n%s", name, output)
		}
		if name == "host-local" && !strings.Contains(string(output), "target-pod-reachable private or public HTTPS") {
			t.Fatalf("host-local endpoint rejection is not actionable:\n%s", output)
		}
		if name == "insecure-ingress" && !strings.Contains(string(output), "access.ingress.tls.enabled=true") {
			t.Fatalf("Ingress TLS prerequisite rejection is not actionable:\n%s", output)
		}
	}

	legacy := renderUmbrella(t, "--set", "global.envplane.remoteControlPlane.endpoint=https://legacy.envplane.example.test")
	if !strings.Contains(legacy, `name: ENVPLANE_MANAGEMENT_ENDPOINT_BOOTSTRAP_URL`) || !strings.Contains(legacy, `value: "https://legacy.envplane.example.test"`) {
		t.Fatalf("legacy endpoint values must remain a one-time bootstrap source:\n%s", legacy)
	}
	cmd := exec.Command("helm", append([]string{"template", "envplane", chartPath}, withFixturePostgres([]string{
		"--set", "global.envplane.remoteControlPlane.endpoint=https://legacy.envplane.example.test",
		"--set", "global.envplane.managementEndpointProfile.bootstrap.endpoint=https://different.envplane.example.test",
	})...)...)
	cmd.Dir = chartPath
	if output, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(output), "conflict") {
		t.Fatalf("conflicting legacy and bootstrap profile values must fail safely: %v\n%s", err, output)
	}
}

func TestUmbrellaE2EFixtureProfileOwnsRuntimeAndFixtureWorkloads(t *testing.T) {
	rendered := renderUmbrella(t, "--values", "values-e2e-local.yaml")
	for _, expected := range []string{
		"# Source: envplane/charts/envplane-agent/templates/deployment.yaml",
		"# Source: envplane/charts/envplane-runner/templates/deployment.yaml",
		`name: "envplane-e2e-base"`,
		`name: "envplane-e2e-feature"`,
		"name: e2e-base-workload",
		"name: ENVPLANE_SAME_CLUSTER_FIXTURE_ENABLED",
		"name: ENVPLANE_SAME_CLUSTER_FIXTURE_RECOVERY_ENABLED",
		`value: "true"`,
		`value: "oci://ghcr.io/envplane/envplane-e2e-workload"`,
		`value: "envplane-e2e-base"`,
		`value: "envplane-e2e-feature"`,
		"agent-registration-token",
		"runner-registration-token",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("E2E fixture render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "ENVPLANE_SAME_CLUSTER_FIXTURE_ENABLED\n              value: \"false\"") {
		t.Fatalf("E2E fixture profile did not enable control-plane reconciliation:\n%s", rendered)
	}
	if strings.Contains(rendered, "# Source: envplane/charts/envplane-control-plane/templates/hpa.yaml") {
		t.Fatalf("local E2E profile must not render an HPA when metrics-server is unavailable:\n%s", rendered)
	}
}

func TestUmbrellaFixtureRecoveryIsExplicitlyOptIn(t *testing.T) {
	rendered := renderUmbrella(t, "--values", "values-e2e-local.yaml", "--set", "global.envplane.e2eFixture.recovery.enabled=false")
	if !strings.Contains(rendered, "name: ENVPLANE_SAME_CLUSTER_FIXTURE_RECOVERY_ENABLED\n              value: \"false\"") {
		t.Fatalf("fixture recovery must be disabled unless explicitly opted in:\n%s", rendered)
	}
	if strings.Contains(rendered, "runnerRegistrationToken") || strings.Contains(rendered, "agentRegistrationToken") {
		t.Fatalf("fixture render must not embed raw bootstrap credentials:\n%s", rendered)
	}
	if !strings.Contains(rendered, "name: ENVPLANE_SAME_CLUSTER_FIXTURE_CHART_VERSION\n              value: \"0.1.0\"") {
		t.Fatalf("fixture must pass the immutable OCI chart version to control-plane:\n%s", rendered)
	}
}

func TestUmbrellaRejectsFixtureWithoutChartManagedRuntime(t *testing.T) {
	buildDependencies(t)
	chartPath := umbrellaChartPath(t)
	cmd := exec.Command("helm", append([]string{"template", "envplane", chartPath}, withFixturePostgres([]string{
		"--set", "global.envplane.e2eFixture.enabled=true",
		"--set", "global.envplane.firstStartRegistration.mode=disabled",
	})...)...)
	cmd.Dir = chartPath
	output, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "requires managed or existing firstStartRegistration") {
		t.Fatalf("fixture without first-start runtime must fail, err=%v output=%s", err, output)
	}
}

func TestUmbrellaDirectlyOwnsDefaultWorkloads(t *testing.T) {
	rendered := renderUmbrella(t)
	for _, expected := range []string{
		"# Source: envplane/charts/envplane-control-plane/templates/deployment.yaml",
		"# Source: envplane/charts/envplane-frontend/templates/deployment.yaml",
		"# Source: envplane/charts/envplane-agent/templates/deployment.yaml",
		"# Source: envplane/charts/envplane-runner/templates/deployment.yaml",
		"name: envplane-control-plane",
		"name: envplane-frontend",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("umbrella render missing direct child workload %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{
		"name: envplane-install",
		"ghcr.io/envplane/install",
		"kubectl delete namespace",
		"kind: Ingress",
		"kind: HTTPRoute",
		"envplane.local",
	} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("umbrella render contains retired installer behavior %q:\n%s", forbidden, rendered)
		}
	}
	for _, disabled := range []string{"# Source: envplane/charts/envplane-webhook/templates/deployment.yaml"} {
		if strings.Contains(rendered, disabled) {
			t.Fatalf("Webhook must remain opt-in by default; found %q", disabled)
		}
	}
	if !strings.Contains(rendered, "          envFrom:\n            - configMapRef:\n                name: \"envplane-platform-dependency-status\"") {
		t.Fatalf("platform dependency status must be injected into the API container:\n%s", rendered)
	}
	if strings.Contains(rendered, "      envFrom:\n        - configMapRef:") {
		t.Fatalf("platform dependency status must not be rendered at PodSpec scope:\n%s", rendered)
	}
}

func TestUmbrellaPersistsBootstrapRuntimeRetirementContract(t *testing.T) {
	rendered, err := renderPublishedUmbrella(t,
		"--set", "global.envplane.sameClusterProjectExecutors.enabled=true",
		"--set", "global.envplane.sameClusterProjectExecutors.namespace=envplane-executors",
	)
	if err != nil {
		t.Fatalf("render published umbrella with bootstrap runtime handoff: %v\n%s", err, rendered)
	}
	for _, expected := range []string{
		"name: \"envplane-bootstrap-runtime-lifecycle\"",
		"envplane.io/bootstrap-runtime-lifecycle: \"true\"",
		"status: \"active\"",
		"envplane.io/bootstrap-runtime: \"true\"",
		"envplane.io/bootstrap-runtime-component: agent",
		"envplane.io/bootstrap-runtime-component: runner",
		"name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_RETIREMENT_ENABLED",
		"name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_NAMESPACE",
		"fieldPath: metadata.namespace",
		"name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_AGENT_DEPLOYMENT",
		"name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNNER_DEPLOYMENT",
		"name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_STATE_CONFIG_MAP",
		"resourceNames: [\"envplane-bootstrap-runtime-lifecycle\"]",
		"resourceNames: [\"envplane-agent\", \"envplane-runner\"]",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("bootstrap runtime handoff render missing %q:\n%s", expected, rendered)
		}
	}
}

func TestZeroValuesProfileUsesManagedCredentialsAndPortForwardAccess(t *testing.T) {
	rendered := renderUmbrella(t)
	for _, expected := range []string{
		"name: envplane-first-start-registration",
		"agent-registration-token:",
		"runner-registration-token:",
		"runner-project-config-token:",
		"name: ENVPLANE_SAME_CLUSTER_REGISTRATION_ENABLED",
		"kind: PersistentVolumeClaim",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("zero-values render missing %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{"kind: Ingress", "kind: HTTPRoute", "imagePullSecrets:", "stringData:"} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("zero-values render contains forbidden %q:\n%s", forbidden, rendered)
		}
	}
	notes, err := os.ReadFile("../templates/NOTES.txt")
	if err != nil {
		t.Fatalf("read zero-values NOTES: %v", err)
	}
	if !strings.Contains(string(notes), "kubectl -n {{ .Release.Namespace }} port-forward svc/envplane-frontend 3000:3000") {
		t.Fatalf("zero-values NOTES must include the no-add-on port-forward fallback")
	}
}

func TestZeroValuesProfileValidatesExplicitStorageClass(t *testing.T) {
	output := renderUmbrellaError(t,
		"--set", "envplane-control-plane.persistence.storageClassName=missing-storage-class",
	)
	if !strings.Contains(output, "StorageClass \"missing-storage-class\" was not found or the Helm operator cannot read") {
		t.Fatalf("explicit StorageClass failure must be actionable:\n%s", output)
	}
}

func TestUmbrellaRegistrySecretPropagatesToEveryRuntimePod(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
	)
	for _, expected := range []string{
		"# Source: envplane/templates/registry-preflight-job.yaml",
		"# Source: envplane/charts/envplane-control-plane/templates/deployment.yaml",
		"# Source: envplane/charts/envplane-frontend/templates/deployment.yaml",
		"# Source: envplane/charts/envplane-agent/templates/deployment.yaml",
		"# Source: envplane/charts/envplane-runner/templates/deployment.yaml",
		"name: registry-credentials",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("private registry render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "dockerconfigjson:") || strings.Contains(rendered, "registry-auth:") {
		t.Fatalf("rendered chart must contain only registry Secret references, not credential data:\n%s", rendered)
	}

	chartPath := umbrellaChartPath(t)
	cmd := exec.Command("helm", "template", "envplane", chartPath, "--set", "global.envplane.registry.mode=existing")
	cmd.Dir = chartPath
	output, err := cmd.CombinedOutput()
	if err == nil || (!strings.Contains(string(output), "global.envplane.registry.existingSecret is required") && !strings.Contains(string(output), "existingSecret")) {
		t.Fatalf("missing registry Secret reference must fail early, err=%v output=%s", err, output)
	}
}

func TestChildChartsShareExplicitImageContract(t *testing.T) {
	components := []string{
		"envplane-control-plane",
		"envplane-frontend",
		"envplane-agent",
		"envplane-runner",
	}

	for _, component := range components {
		imageName := strings.TrimPrefix(component, "envplane-")
		rendered := renderChildChart(t, component,
			"--set", "image.repository=registry.example.internal/envplane/"+imageName,
			"--set", "image.tag=build-20260731",
			"--set", "image.digest=",
			"--set", "image.pullPolicy=Always",
			"--set", "image.sourceRevision=abcdef123456",
			"--set", "image.release=2026.07.31",
			"--set", "imagePullSecrets[0].name=private-registry",
		)
		for _, expected := range []string{
			`image: "registry.example.internal/envplane/` + imageName + `:build-20260731"`,
			"imagePullPolicy: Always",
			"envplane.io/source-revision: abcdef123456",
			"envplane.io/release: 2026.07.31",
		} {
			if !strings.Contains(rendered, expected) {
				t.Fatalf("%s tag/private-registry render missing %q:\n%s", component, expected, rendered)
			}
		}
		if !strings.Contains(rendered, "name: private-registry") {
			t.Fatalf("%s private registry pull secret was not rendered:\n%s", component, rendered)
		}
	}

	const digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	for _, component := range components {
		imageName := strings.TrimPrefix(component, "envplane-")
		digestRender := renderChildChart(t, component,
			"--set", "image.repository=registry.example.internal/envplane/"+imageName,
			"--set", "image.tag=must-not-be-rendered",
			"--set", "image.digest="+digest,
		)
		expected := `image: "registry.example.internal/envplane/` + imageName + `@` + digest + `"`
		if !strings.Contains(digestRender, expected) {
			t.Fatalf("%s digest render missing %q:\n%s", component, expected, digestRender)
		}
		forbidden := `image: "registry.example.internal/envplane/` + imageName + `:must-not-be-rendered"`
		if strings.Contains(digestRender, forbidden) {
			t.Fatalf("%s rendered tag image while digest was configured:\n%s", component, digestRender)
		}
	}
}

func TestChildChartsRejectImplicitLatestAndSharedTagOverride(t *testing.T) {
	for _, path := range []string{"../values.yaml", "../values.schema.json"} {
		contents, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		if strings.Contains(string(contents), "images.tag") || strings.Contains(string(contents), "\"images\"") {
			t.Fatalf("deprecated shared images.tag override remains in %s", path)
		}
	}

	buildDependencies(t)
	for _, component := range []string{"envplane-control-plane", "envplane-frontend", "envplane-agent", "envplane-runner"} {
		chartPath := umbrellaChartPath(t)
		for _, invalid := range []struct {
			value   string
			message string
		}{
			{value: "latest", message: "image.tag must not be latest"},
			{value: "", message: "image.tag is required when image.digest is not set"},
		} {
			// Some child charts intentionally ship a digest default. Clear it here so
			// this assertion exercises the tag-validation branch rather than digest
			// precedence.
			args := withFixturePostgres([]string{
				"template", "envplane", chartPath,
				"--set", component + ".image.tag=" + invalid.value,
				"--set", component + ".image.digest=",
			})
			if component == "envplane-agent" {
				args = append(args, "--set", "agent.enabled=true")
			}
			if component == "envplane-runner" {
				args = append(args, "--set", "runner.enabled=true")
			}
			cmd := exec.Command("helm", args...)
			cmd.Dir = chartPath
			output, err := cmd.CombinedOutput()
			if err == nil || !strings.Contains(string(output), invalid.message) {
				t.Fatalf("%s accepted invalid image tag %q, err=%v output=%s", component, invalid.value, err, output)
			}
		}
	}
}

func TestProviderNeutralAccessRendersIngressAndGatewayOnlyWhenExplicit(t *testing.T) {
	ingress := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envplane.example.internal",
		"--set", "access.ingress.className=shared-ingress",
		"--set", "access.ingress.annotations.example\\.io/owner=platform",
	)
	for _, expected := range []string{
		"kind: Ingress",
		"host: \"envplane.example.internal\"",
		"ingressClassName: \"shared-ingress\"",
		"example.io/owner: platform",
		"name: envplane-control-plane",
		"name: envplane-frontend",
	} {
		if !strings.Contains(ingress, expected) {
			t.Fatalf("provider-neutral ingress render missing %q:\n%s", expected, ingress)
		}
	}

	gateway := renderUmbrella(t,
		"--set", "access.mode=gateway",
		"--set", "access.gateway.name=shared-gateway",
		"--set", "access.gateway.namespace=gateway-system",
		"--set", "access.gateway.sectionName=https",
		"--set", "access.gateway.hostnames[0]=envplane.example.internal",
	)
	for _, expected := range []string{
		"apiVersion: gateway.networking.k8s.io/v1",
		"kind: HTTPRoute",
		"name: \"shared-gateway\"",
		"namespace: \"gateway-system\"",
		"sectionName: \"https\"",
		"- envplane.example.internal",
	} {
		if !strings.Contains(gateway, expected) {
			t.Fatalf("provider-neutral gateway render missing %q:\n%s", expected, gateway)
		}
	}
}

func TestProviderNeutralProfilesRenderDeclaredAccessAndServiceModes(t *testing.T) {
	tests := []struct {
		name      string
		profile   string
		expected  []string
		forbidden []string
	}{
		{
			name:    "generic Kubernetes",
			profile: "generic-kubernetes.yaml",
			expected: []string{
				"type: ClusterIP",
				"ENVPLANE_PLATFORM_INGRESS_MODE: \"disabled\"",
			},
			forbidden: []string{"kind: Ingress", "kind: HTTPRoute", "alb.ingress.kubernetes.io"},
		},
		{
			name:    "nginx ingress",
			profile: "nginx-ingress.yaml",
			expected: []string{
				"kind: Ingress",
				"ingressClassName: \"nginx\"",
				"ENVPLANE_PLATFORM_INGRESS_PROVIDER: \"nginx\"",
			},
			forbidden: []string{"alb.ingress.kubernetes.io", "kind: HTTPRoute"},
		},
		{
			name:    "AWS ALB",
			profile: "aws-alb.yaml",
			expected: []string{
				"ingressClassName: \"alb\"",
				"alb.ingress.kubernetes.io/scheme: internet-facing",
				"ENVPLANE_PLATFORM_DNS_PROVIDER: \"external-dns\"",
			},
			forbidden: []string{"kind: HTTPRoute"},
		},
		{
			name:    "Gateway API",
			profile: "gateway-api.yaml",
			expected: []string{
				"kind: HTTPRoute",
				"name: \"shared-gateway\"",
				"ENVPLANE_PLATFORM_INGRESS_PROVIDER: \"gateway-api\"",
			},
			forbidden: []string{"kind: Ingress"},
		},
		{
			name:    "NodePort",
			profile: "nodeport.yaml",
			expected: []string{
				"type: NodePort",
				"nodePort: 30080",
				"nodePort: 30081",
			},
			forbidden: []string{"kind: Ingress", "kind: HTTPRoute"},
		},
		{
			name:      "LoadBalancer",
			profile:   "loadbalancer.yaml",
			expected:  []string{"type: LoadBalancer"},
			forbidden: []string{"kind: Ingress", "kind: HTTPRoute"},
		},
		{
			name:    "external data services",
			profile: "external-data-services.yaml",
			expected: []string{
				"name: \"envplane-postgres-url\"",
				"name: \"envplane-redis-url\"",
			},
			forbidden: []string{
				"# Source: envplane/charts/envplane-control-plane/templates/postgres.yaml",
				"# Source: envplane/charts/envplane-control-plane/templates/redis.yaml",
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			rendered := renderUmbrella(t, "--values", filepath.Join("profiles", tc.profile))
			for _, expected := range tc.expected {
				if !strings.Contains(rendered, expected) {
					t.Fatalf("profile %s missing %q:\n%s", tc.profile, expected, rendered)
				}
			}
			for _, forbidden := range tc.forbidden {
				if strings.Contains(rendered, forbidden) {
					t.Fatalf("profile %s retained forbidden %q:\n%s", tc.profile, forbidden, rendered)
				}
			}
		})
	}
}

func TestPlatformDependencyStatusContractIsRenderedForControlPlane(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.provider=nginx",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
		"--set", "platformDependencies.dns.mode=disabled",
		"--set", "platformDependencies.storage.mode=managed",
		"--set", "platformDependencies.storage.provider=local-path",
		"--set", "platformDependencies.storage.ownership=envplane",
		"--set", "platformDependencies.storage.managed.chartRef=oci://ghcr.io/example/local-path",
		"--set", "platformDependencies.storage.managed.version=1.0.0",
		"--set", "platformDependencies.storage.managed.releaseName=local-path",
	)
	for _, expected := range []string{
		"name: envplane-platform-dependency-status",
		"ENVPLANE_PLATFORM_INGRESS_PROVIDER: \"nginx\"",
		"ENVPLANE_PLATFORM_INGRESS_REFERENCE: \"ingress-nginx\"",
		"ENVPLANE_PLATFORM_INGRESS_OWNERSHIP: \"external\"",
		"ENVPLANE_PLATFORM_INGRESS_STATE: \"detected\"",
		"ENVPLANE_PLATFORM_STORAGE_PROVIDER: \"local-path\"",
		"ENVPLANE_PLATFORM_STORAGE_STATE: \"managed\"",
		"configMapRef:",
		"name: \"envplane-platform-dependency-status\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("platform dependency contract missing %q:\n%s", expected, rendered)
		}
	}
}

func TestControlPlaneWatchesScopedReconcilerStatus(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.className=nginx",
		"--set", "access.ingress.host=envplane.example.test",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envplane-control-plane-platform-dependency-status-reader",
		"resources: [\"configmaps\"]",
		"verbs: [\"get\", \"watch\"]",
		"name: ENVPLANE_PLATFORM_DEPENDENCY_STATUS_CONFIG_MAP",
		"value: \"envplane-platform-dependency-reconciler-status-r1\"",
		"name: ENVPLANE_PLATFORM_DEPENDENCY_STATUS_STALE_AFTER_SECONDS",
		"value: \"300\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("control-plane reconciler status watcher missing %q:\n%s", expected, rendered)
		}
	}
}

func TestPlatformDependencyReconcilerSupportIsReleaseOwnedAndLeastPrivilege(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
		"--set", "platformDependencyReconciler.cleanupManagedOnUninstall=true",
	)
	for _, expected := range []string{
		"\"helm.sh/hook\": post-install,post-upgrade",
		"\"helm.sh/hook\": pre-delete",
		"resources: [\"ingressclasses\"]",
		"resources: [\"storageclasses\"]",
		"app.kubernetes.io/component: platform-reconciler",
		"ENVPLANE_RECONCILE_CONFIG_JSON",
		"name: HOME\n              value: /tmp/envplane-home",
		"name: XDG_CACHE_HOME\n              value: /tmp/envplane-home/.cache",
		"mountPath: /tmp",
		"\"helm.sh/hook-delete-policy\": before-hook-creation,hook-succeeded,hook-failed",
		"app.kubernetes.io/managed-by: Helm",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("platform reconciler contract missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "resources: [\"deployments\", \"pods\"]") || strings.Contains(rendered, "helm.sh/hook: post-install") {
		t.Fatal("platform reconciler must not own EnvPlane core workloads")
	}
}

func TestNginxCleanInstallHooksAreActionAwareAndFailureSafe(t *testing.T) {
	existing := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	if strings.Contains(existing, "platform-reconciler-namespaces") {
		t.Fatalf("existing nginx must not render namespace setup hook:\n%s", existing)
	}
	if !strings.Contains(existing, "name: envplane-platform-reconciler\n") ||
		!strings.Contains(existing, "\"helm.sh/hook-delete-policy\": before-hook-creation,hook-succeeded,hook-failed") {
		t.Fatalf("existing nginx must render a self-cleaning reconciler hook:\n%s", existing)
	}

	managed := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envplane.example.test",
		"--set", "access.ingress.className=nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envplane-platform-reconciler-namespaces",
		"name: ENVPLANE_RECONCILE_ACTION\n              value: ensure-namespaces",
		"name: ENVPLANE_RECONCILE_PROVIDER_NAMESPACES",
		"\"helm.sh/hook-delete-policy\": before-hook-creation,hook-succeeded,hook-failed",
	} {
		if !strings.Contains(managed, expected) {
			t.Fatalf("managed nginx clean-install hook contract missing %q:\n%s", expected, managed)
		}
	}
	if strings.Contains(managed, "ENVPLANE_RECONCILE_CONFIG_JSON\n              value:") {
		t.Fatalf("namespace setup must not receive an inline dependency config:\n%s", managed)
	}
}

func TestPlatformReconcilerStatusConfigMapIsHelmOwnedAndWriteScoped(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envplane-platform-dependency-reconciler-status-r1",
		"status.json: \"\"",
		"resourceNames: [\"envplane-platform-dependency-reconciler\", \"envplane-platform-dependency-reconciler-status-r1\"]",
		"verbs: [\"get\", \"update\", \"patch\"]",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("platform reconciler release-owned status contract missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "verbs: [\"create\"]\n  - apiGroups: [\"\"]\n    resources: [\"configmaps\"]") {
		t.Fatalf("platform reconciler must not retain broad ConfigMap create permission:\n%s", rendered)
	}
}

func TestReleaseOwnedConfigMapsAreRevisionScopedForServerSideUpgrades(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envplane-platform-dependency-reconciler-status-r1",
		"value: \"envplane-platform-dependency-reconciler-status-r1\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("revision-scoped reconciler status contract missing %q:\\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "name: envplane-platform-dependency-reconciler-status\\n") {
		t.Fatalf("status ConfigMap must not retain an unversioned name:\\n%s", rendered)
	}

	compatibilityTemplate, err := os.ReadFile("../templates/remote-cluster-compatibility-configmap.yaml")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(compatibilityTemplate), "envplane.remoteClusterCompatibilityConfigMapName") ||
		strings.Contains(string(compatibilityTemplate), "name: {{ .Release.Name }}-remote-cluster-compatibility") {
		t.Fatalf("immutable compatibility map must use the revision-scoped helper:\\n%s", compatibilityTemplate)
	}

	childRoot := t.TempDir()
	childPath := filepath.Join(childRoot, "envplane-control-plane")
	canonicalRoot, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	copyChartTree(t, filepath.Join(canonicalRoot, "envplane-control-plane"), childPath)
	copyChartTree(t, filepath.Join(canonicalRoot, "envplane-frontend"), filepath.Join(childRoot, "envplane-frontend"))
	dependencies := exec.Command("helm", "dependency", "build", "--skip-refresh", childPath)
	dependencyOutput, err := dependencies.CombinedOutput()
	if err != nil {
		t.Fatalf("build control-plane child dependencies: %v\n%s", err, dependencyOutput)
	}
	child := exec.Command("helm", append([]string{"template", "envplane", childPath, "--namespace", "envplane"}, withChildFixturePostgres([]string{
		"--set", "global.envplane.remoteClusterReconciler.enabled=true",
		"--set", "rbac.remoteClusterReconciler.enabled=true",
	})...)...)
	child.Dir = "."
	childRendered, err := child.CombinedOutput()
	if err != nil {
		t.Fatalf("render control-plane compatibility consumer: %v\\n%s", err, childRendered)
	}
	for _, expected := range []string{"name: \"envplane-remote-cluster-compatibility-r1\""} {
		if !strings.Contains(string(childRendered), expected) {
			t.Fatalf("control-plane must consume revision-scoped compatibility map %q:\\n%s", expected, childRendered)
		}
	}
}

func TestPlatformReconcilerSupportsPrivateRegistryPullSecrets(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencyReconciler.imagePullSecrets[0].name=ghcr-envplane",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
	)
	for _, expected := range []string{
		"name: envplane-platform-reconciler",
		"imagePullSecrets:\n        - name: ghcr-envplane",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("platform reconciler private-registry render missing %q:\n%s", expected, rendered)
		}
	}
}

func TestPlatformReconcilerPrerequisitesRunBeforeTheGateJob(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envplane.example.test",
		"--set", "access.ingress.className=nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envplane-platform-dependency-reconciler\n  namespace: envplane\n  labels:\n    app.kubernetes.io/name: envplane",
		"name: envplane-platform-reconciler\n  namespace: envplane\n  labels:\n    app.kubernetes.io/name: envplane",
		"name: envplane-platform-reconciler-namespaces\n  namespace: envplane\n  annotations:\n    \"helm.sh/hook\": post-install,post-upgrade\n    \"helm.sh/hook-weight\": \"-30\"",
		"name: envplane-platform-reconciler\n  namespace: envplane\n  annotations:\n    \"helm.sh/hook\": post-install,post-upgrade\n    \"helm.sh/hook-weight\": \"10\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("platform reconciler lifecycle ordering missing %q:\n%s", expected, rendered)
		}
	}
}

func TestPlatformReconcilerIsOptInWhenNoProvidersAreConfigured(t *testing.T) {
	rendered := renderUmbrella(t, "--set", "platformDependencyReconciler.enabled=true")
	for _, forbidden := range []string{
		"platform-reconciler/templates/platform-dependency-reconciler-job.yaml",
		"platform-dependency-reconciler-cleanup",
		"platform-reconciler-discovery",
	} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("reconciler must not render without an enabled provider %q:\n%s", forbidden, rendered)
		}
	}
}

func TestPlatformReconcilerUsesPublicArtifactsWithoutRegistryCredentials(t *testing.T) {
	rendered := renderUmbrella(t, withFixturePostgres([]string{
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
	})...)
	if !strings.Contains(rendered, "name: envplane-platform-reconciler") {
		t.Fatalf("public reconciler artifacts must render without a registry Secret:\n%s", rendered)
	}
	if strings.Contains(rendered, "imagePullSecrets:") || strings.Contains(rendered, "registry-preflight") {
		t.Fatalf("public reconciler render must not reference a registry Secret:\n%s", rendered)
	}
}

func TestPlatformReconcilerCleanupIsBoundedAndFailureSafe(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencyReconciler.cleanupManagedOnUninstall=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"\"helm.sh/hook\": pre-delete",
		"\"helm.sh/hook-delete-policy\": before-hook-creation,hook-succeeded,hook-failed",
		"activeDeadlineSeconds: 120",
		"ttlSecondsAfterFinished: 30",
		"backoffLimit: 4",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("bounded cleanup contract missing %q:\n%s", expected, rendered)
		}
	}
}

func TestManagedIngressProviderRendersPinnedSmokeContract(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
		"--set", "platformDependencies.ingress.mode=managed",
		"--set", "platformDependencies.ingress.provider=nginx",
		"--set", "platformDependencies.ingress.ownership=envplane",
		"--set", "platformDependencies.ingress.managed.chartRef=https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-4.11.0/ingress-nginx-4.11.0.tgz",
		"--set", "platformDependencies.ingress.managed.version=4.11.0",
		"--set", "platformDependencies.ingress.managed.releaseName=envplane-ingress-nginx",
		"--set", "platformDependencies.ingress.managed.smoke.serviceName=envplane-frontend",
		"--set", "platformDependencies.ingress.managed.smoke.namespace=envplane",
		"--set", "platformDependencies.ingress.managed.smoke.port=3000",
		"--set", "platformDependencies.ingress.managed.smoke.host=envplane.example.test",
	)
	for _, expected := range []string{"resources: [\"services\", \"endpoints\"]", "resources: [\"ingresses\"]", "ENVPLANE_RECONCILE_ACTION", "envplane.example.test"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("managed ingress contract missing %q:\n%s", expected, rendered)
		}
	}
}

func TestIngressAccessProfileAutomaticallyReconcilesMissingNginxController(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envplane.example.test",
		"--set", "access.ingress.className=nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"kind: Ingress",
		"ingressClassName: \"nginx\"",
		"kind: Job",
		"name: envplane-platform-reconciler",
		"ENVPLANE_RECONCILE_CONFIG_JSON",
		"mode\\\":\\\"auto\\\"",
		"provider\\\":\\\"nginx\\\"",
		"helm-chart-4.11.0/ingress-nginx-4.11.0.tgz",
		"releaseName\\\":\\\"envplane-ingress-nginx\\\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("ingress access profile missing automatic controller reconciliation %q:\n%s", expected, rendered)
		}
	}
}

func TestIngressAccessProfileGrantsOnlyScopedProviderInstallerPermissions(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envplane.example.test",
		"--set", "access.ingress.className=nginx",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"resources: [\"namespaces\"]\n    verbs: [\"get\", \"create\"]",
		"resources: [\"clusterroles\", \"clusterrolebindings\"]",
		"resources: [\"validatingwebhookconfigurations\"]",
		"resources: [\"configmaps\", \"pods\", \"secrets\"]\n    verbs: [\"list\", \"watch\"]",
		"name: envplane-platform-reconciler-ingress-installer",
		"namespace: ingress-nginx",
		"resources: [\"configmaps\", \"endpoints\", \"events\", \"pods\", \"secrets\", \"serviceaccounts\", \"services\"]",
		"name: envplane-platform-reconciler-namespaces",
		"ENVPLANE_RECONCILE_PROVIDER_NAMESPACES",
		"\"helm.sh/hook\": post-install,post-upgrade",
		"\"helm.sh/hook-weight\": \"-30\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("nginx provider installer permissions missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "resources: [\"*\"]") || strings.Contains(rendered, "verbs: [\"*\"]") {
		t.Fatal("nginx provider installer must not render wildcard RBAC")
	}
}

func TestIngressAccessProfileDoesNotAutoInstallNonNginxClass(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envplane.example.test",
		"--set", "access.ingress.className=alb",
	)
	if strings.Contains(rendered, "platform-reconciler-discovery") || strings.Contains(rendered, "kind: Job\nmetadata:\n  name: envplane-platform-reconciler") {
		t.Fatalf("non-nginx ingress class must not implicitly install a provider:\n%s", rendered)
	}
}

func TestManagedExternalDNSRendersScopedContract(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
		"--set", "platformDependencies.dns.mode=managed",
		"--set", "platformDependencies.dns.provider=external-dns",
		"--set", "platformDependencies.dns.ownership=envplane",
		"--set", "platformDependencies.dns.credentials.existingSecret=dns-credentials",
		"--set", "platformDependencies.dns.domainFilters[0]=example.test",
		"--set", "platformDependencies.dns.ownershipId=envplane",
		"--set", "platformDependencies.dns.policy=sync",
		"--set", "platformDependencies.dns.managed.chartRef=oci://ghcr.io/kubernetes-sigs/external-dns/external-dns",
		"--set", "platformDependencies.dns.managed.version=1.15.0",
		"--set", "platformDependencies.dns.managed.releaseName=envplane-external-dns",
	)
	for _, expected := range []string{"resources: [\"deployments\"]", "resources: [\"secrets\"]", "dns-credentials", "example.test", "envplane-external-dns"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("managed DNS contract missing %q:\n%s", expected, rendered)
		}
	}
}

func TestManagedLocalPathStorageRendersSmokeContract(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
		"--set", "platformDependencies.storage.mode=managed",
		"--set", "platformDependencies.storage.provider=local-path-provisioner",
		"--set", "platformDependencies.storage.ownership=envplane",
		"--set", "platformDependencies.storage.managed.chartRef=oci://ghcr.io/rancher/local-path-provisioner",
		"--set", "platformDependencies.storage.managed.version=0.0.28",
		"--set", "platformDependencies.storage.managed.releaseName=envplane-local-path",
	)
	for _, expected := range []string{"resources: [\"storageclasses\"]", "resources: [\"csidrivers\"]", "resources: [\"persistentvolumeclaims\"]", "local-path-provisioner", "envplane-local-path"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("managed storage contract missing %q:\n%s", expected, rendered)
		}
	}
	gated := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "global.envplane.registry.mode=existing",
		"--set", "global.envplane.registry.existingSecret=registry-credentials",
		"--set", "platformDependencies.storage.mode=existing",
		"--set", "platformDependencies.storage.existingClassName=standard",
		"--set", "platformDependencies.storage.provider=local-path-provisioner",
	)
	if !strings.Contains(gated, "ENVPLANE_RECONCILE_GATE_STORAGE") {
		t.Fatalf("bundled database storage gate was not rendered:\n%s", gated)
	}
}

func TestPlatformDependencyE2EMatrixUsesUmbrellaAndOwnershipScenarios(t *testing.T) {
	script, err := os.ReadFile("platform-dependency-matrix.sh")
	if err != nil {
		t.Fatal(err)
	}
	contents := string(script)
	for _, expected := range []string{"helm upgrade --install", "empty existing mixed degraded", "helm uninstall", "platform-dependency-reconciler-status"} {
		if !strings.Contains(contents, expected) {
			t.Fatalf("platform E2E matrix missing %q", expected)
		}
	}
}

func TestPlatformReconcilerLifecycleE2ECoversUninstallAndCleanReinstall(t *testing.T) {
	script, err := os.ReadFile("platform-reconciler-lifecycle.sh")
	if err != nil {
		t.Fatal(err)
	}
	contents := string(script)
	for _, expected := range []string{
		"helm upgrade --install", "helm uninstall", "assert_owned_support_absent",
		"platform-dependency-reconciler-status", "PLATFORM_RECONCILER_LIFECYCLE_REGISTRY_SECRET",
		"get ingressclass", "must not need manual deletion",
	} {
		if !strings.Contains(contents, expected) {
			t.Fatalf("platform reconciler lifecycle E2E missing %q", expected)
		}
	}
}

func TestPlatformReconcilerLegacyMigrationOnlyTargetsSupportObjects(t *testing.T) {
	template, err := os.ReadFile("../templates/platform-dependency-reconciler-legacy-migration.yaml")
	if err != nil {
		t.Fatal(err)
	}
	contents := string(template)
	for _, expected := range []string{
		"lookup $item.apiVersion $item.kind", "pre-install,pre-upgrade",
		"before-hook-creation,hook-succeeded,hook-failed",
		"platform-dependency-reconciler-status", "platform-reconciler-discovery",
		"platform-reconciler-status", "platform-reconciler-ingress-installer",
	} {
		if !strings.Contains(contents, expected) {
			t.Fatalf("legacy migration contract missing %q", expected)
		}
	}
	for _, forbidden := range []string{"registry Secret", "kind: Secret", "ingressclasses", "existingSecret"} {
		if strings.Contains(contents, forbidden) {
			t.Fatalf("legacy migration must not target external object %q", forbidden)
		}
	}
}

func TestUmbrellaContractMatrixCoversProfilesAndPolicies(t *testing.T) {
	script, err := os.ReadFile("umbrella-contract-matrix.sh")
	if err != nil {
		t.Fatal(err)
	}
	contents := string(script)
	for _, expected := range []string{
		"minimal all-enabled external-databases ingress gateway private-registry existing-secrets",
		"helm lint", "helm template", "kubeconform", "1.26.0", "1.29.0", "1.32.0",
		"duplicate rendered resource", "namespace leakage", "envplane-install", "cluster-admin",
	} {
		if !strings.Contains(contents, expected) {
			t.Fatalf("umbrella contract matrix missing %q", expected)
		}
	}
}

func TestPublishedArtifactE2EContract(t *testing.T) {
	script, err := os.ReadFile("../../../../scripts/published-artifact-e2e.sh")
	if err != nil {
		t.Fatal(err)
	}
	contents := string(script)
	for _, expected := range []string{
		"helm upgrade --install", "--values", "api/v1/health", "api/v1/projects/", "api/v1/environments",
		"helm upgrade", "--reset-values", "helm rollback", "helm uninstall", "ENVPLANE_E2E_EXISTING_RESOURCES",
	} {
		if !strings.Contains(contents, expected) {
			t.Fatalf("published artifact E2E missing %q", expected)
		}
	}
	for _, forbidden := range []string{"minikube start", "kind create cluster", "kubeadm"} {
		if strings.Contains(contents, forbidden) {
			t.Fatalf("published artifact E2E must not provision clusters: %q", forbidden)
		}
	}
}

func TestPublishedUmbrellaRejectsStaleOrConflictingRuntimeImagePins(t *testing.T) {
	rendered, err := renderPublishedUmbrella(t)
	if err != nil {
		t.Fatalf("published umbrella defaults must satisfy its compatibility manifest: %v\n%s", err, rendered)
	}
	if !strings.Contains(rendered, "name: envplane-control-plane") {
		t.Fatalf("published umbrella render unexpectedly omitted the control plane:\n%s", rendered)
	}

	output, err := renderPublishedUmbrella(t,
		"--set", "envplane-control-plane.image.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	)
	if err == nil {
		t.Fatalf("published umbrella must reject a stale image pin:\n%s", output)
	}
	for _, expected := range []string{
		"image override for control-plane conflicts",
		"signed compatibility manifest",
		"Do not use --reuse-values",
	} {
		if !strings.Contains(output, expected) {
			t.Fatalf("image-pin rejection missing %q:\n%s", expected, output)
		}
	}
}

func TestPublishedUmbrellaMountsRevisionScopedInstallFlowManifest(t *testing.T) {
	rendered, err := renderPublishedUmbrella(t)
	if err != nil {
		t.Fatalf("render published umbrella: %v\n%s", err, rendered)
	}
	for _, expected := range []string{
		"name: envplane-release-compatibility-r1",
		"envplane.io/purpose: release-compatibility",
		"immutable: true",
		"mountPath: /etc/envplane/release-compatibility",
		"readOnly: true",
		"name: ENVPLANE_INSTALL_FLOW_COMPATIBILITY_MANIFEST",
		"name: ENVPLANE_INSTALL_FLOW_FIRST_RUN_CONTRACT_VERSION",
		"name: ENVPLANE_INSTALL_FLOW_ACTIVATION_CONTRACT_VERSION",
		"name: ENVPLANE_INSTALL_FLOW_ROLLOUT_MODE",
		`name: "envplane-release-compatibility-r1"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("published release compatibility input missing %q:\n%s", expected, rendered)
		}
	}
}

func TestPublishedUmbrellaSeparatesCompatibilityConfigMapsIntoYAMLDocuments(t *testing.T) {
	rendered, err := renderPublishedUmbrella(t,
		"--set", "global.envplane.sameClusterProjectExecutors.enabled=true",
		"--set", "global.envplane.sameClusterProjectExecutors.namespace=envplane-executors",
	)
	if err != nil {
		t.Fatalf("render published umbrella with project executors: %v\n%s", err, rendered)
	}
	releaseStart := strings.Index(rendered, "name: envplane-release-compatibility-r1")
	remoteStart := strings.Index(rendered, "name: envplane-remote-cluster-compatibility-r1")
	if releaseStart < 0 || remoteStart <= releaseStart || !strings.Contains(rendered[releaseStart:remoteStart], "\n---\n") {
		t.Fatalf("release and remote compatibility ConfigMaps must be separate YAML documents:\n%s", rendered)
	}
}

func TestPublishedUmbrellaRejectsInstallFlowPolicyMismatch(t *testing.T) {
	for _, override := range [][]string{
		{"--set", "global.envplane.installFlow.rollout.mode=canary"},
		{"--set", "global.envplane.installFlow.firstRun.contractVersion=v2"},
		{"--set", "global.envplane.installFlow.activation.contractVersion=v2"},
	} {
		output, err := renderPublishedUmbrella(t, override...)
		if err == nil {
			t.Fatalf("published umbrella accepted incompatible install-flow values %v:\n%s", override, output)
		}
		if !strings.Contains(output, "signed compatibility manifest") {
			t.Fatalf("install-flow rejection does not identify signed manifest for %v:\n%s", override, output)
		}
	}
}

func TestUmbrellaUpgradeWrapperPreservesOperatorValuesWithoutReusingArtifactPins(t *testing.T) {
	wrapper, err := os.ReadFile("../../../../scripts/upgrade-umbrella.sh")
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{
		"--operator-values", "--reset-values", "--version", "--timeout", "Do not echo values",
		"compatibility manifest rejects a conflicting", "--reuse-values",
	} {
		if !strings.Contains(string(wrapper), expected) {
			t.Fatalf("umbrella upgrade wrapper missing %q", expected)
		}
	}

	template, err := os.ReadFile("../templates/compatibility-artifact-guard.yaml")
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{
		"compatibility/release.json", "platform-reconciler", "webhook", "signed compatibility manifest", "--reuse-values",
	} {
		if !strings.Contains(string(template), expected) {
			t.Fatalf("artifact guard missing %q", expected)
		}
	}

	docs, err := os.ReadFile("../../../../docs/installation.md")
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{
		"scripts/upgrade-umbrella.sh", "--reset-values", "--reuse-values", "signed compatibility manifest",
	} {
		if !strings.Contains(string(docs), expected) {
			t.Fatalf("installation upgrade documentation missing %q", expected)
		}
	}
}

func TestPublishedConfigMapUpgradeE2ECoversNMinus1RollbackAndUninstall(t *testing.T) {
	script, err := os.ReadFile("../../../../scripts/published-configmap-upgrade-e2e.sh")
	if err != nil {
		t.Fatal(err)
	}
	contents := string(script)
	for _, expected := range []string{
		"ENVPLANE_CONFIGMAP_E2E_CHART_N_MINUS_1",
		"ENVPLANE_CONFIGMAP_E2E_CHART_N",
		"--server-side=true",
		"--field-manager=platform-reconciler",
		"platform-dependency-reconciler-status-r",
		"remote-cluster-compatibility-r",
		"release-compatibility-r",
		"helm rollback",
		"helm uninstall",
	} {
		if !strings.Contains(contents, expected) {
			t.Fatalf("published ConfigMap upgrade E2E missing %q", expected)
		}
	}
	for _, forbidden := range []string{"--force", "--force-conflicts", "kubectl delete configmap"} {
		if strings.Contains(contents, forbidden) {
			t.Fatalf("published ConfigMap upgrade E2E must not require %q", forbidden)
		}
	}
}

func TestInstallationDocsQuickStartSmoke(t *testing.T) {
	docs, err := os.ReadFile("../../../../docs/installation.md")
	if err != nil {
		t.Fatal(err)
	}
	advanced, err := os.ReadFile("../../../../docs/installation-advanced.md")
	if err != nil {
		t.Fatal(err)
	}
	indexBytes, err := os.ReadFile("../../../../docs/generated/stable-release-index.json")
	if err != nil {
		t.Fatal(err)
	}
	var releaseIndex struct {
		Install struct {
			Command string `json:"command"`
		} `json:"install"`
	}
	if err := json.Unmarshal(indexBytes, &releaseIndex); err != nil {
		t.Fatal(err)
	}
	if releaseIndex.Install.Command == "" || !strings.Contains(string(docs), releaseIndex.Install.Command) {
		t.Fatal("installation docs do not contain the signed release-index command")
	}
	contents := string(docs)
	for _, expected := range []string{
		"Kubernetes 1.26", "Free limits and activation", "## Upgrade", "## Uninstall",
		"## Troubleshooting", "does not require", "manual child-chart assembly",
	} {
		if !strings.Contains(contents, expected) {
			t.Fatalf("installation docs missing %q", expected)
		}
	}
	for _, expected := range []string{"Production hardening", "Private registry or mirror", "External PostgreSQL and Redis", "auto", "managed", "existing"} {
		if !strings.Contains(string(advanced), expected) {
			t.Fatalf("advanced installation docs missing %q", expected)
		}
	}
	for _, forbidden := range []string{"helm install envplane-control-plane", "installer Job is required"} {
		if strings.Contains(contents, forbidden) {
			t.Fatalf("installation docs contain unsupported production path %q", forbidden)
		}
	}
}

func TestAllComponentRenderMeetsRestrictedPodSecurityBaseline(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
		"--set", "webhook.enabled=true",
		"--set", "global.envplane.firstStartRegistration.mode=managed",
		"--set", "global.envplane.firstStartRegistration.cluster.id=management",
	)
	for _, expected := range []string{"runAsNonRoot: true", "type: RuntimeDefault", "allowPrivilegeEscalation: false", "- ALL"} {
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

func TestValuesSchemaRejectsInvalidAccessContract(t *testing.T) {
	buildDependencies(t)
	chartPath := umbrellaChartPath(t)
	for _, args := range [][]string{
		{"template", "envplane", chartPath, "--set", "access.mode=not-a-mode"},
		{"template", "envplane", chartPath, "--set", "access.mode=ingress"},
		{"template", "envplane", chartPath, "--set", "access.mode=gateway"},
		{"template", "envplane", chartPath, "--set", "global.envplane.firstStartRegistration.mode=existing"},
	} {
		cmd := exec.Command("helm", args...)
		cmd.Dir = chartPath
		if output, err := cmd.CombinedOutput(); err == nil {
			t.Fatalf("invalid values unexpectedly passed schema: %v\n%s", args, output)
		}
	}
}

func TestFirstStartRegistrationRendersManagedSecretAndSameClusterIdentities(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
		"--set", "global.envplane.firstStartRegistration.mode=managed",
		"--set", "global.envplane.firstStartRegistration.cluster.id=management",
	)
	for _, expected := range []string{
		"name: envplane-first-start-registration",
		"agent-registration-token:",
		"runner-registration-token:",
		"runner-project-config-token:",
		"name: ENVPLANE_SAME_CLUSTER_REGISTRATION_ENABLED",
		"name: ENVPLANE_SAME_CLUSTER_AGENT_REGISTRATION_TOKEN",
		"name: ENVPLANE_SAME_CLUSTER_RUNNER_REGISTRATION_TOKEN",
		"name: ENVPLANE_AGENT_REGISTRATION_TOKEN",
		"name: ENVPLANE_RUNNER_REGISTRATION_TOKEN",
		"name: ENVPLANE_PROJECT_CONFIG_TOKEN",
		`value: "management"`,
		`value: "envplane"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("first-start render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "envplane-agent-install-check") {
		t.Fatalf("first-start mode must not render the token-consuming Agent install-check Job:\n%s", rendered)
	}
	secretTemplate, err := os.ReadFile("../templates/first-start-registration-secret.yaml")
	if err != nil {
		t.Fatalf("read managed registration Secret template: %v", err)
	}
	if !strings.Contains(string(secretTemplate), "lookup \"v1\" \"Secret\"") {
		t.Fatalf("managed registration Secret must preserve credentials through Helm upgrades")
	}
}

func TestFirstStartRegistrationUsesOperatorSecretWithoutRenderingTokens(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
		"--set", "global.envplane.firstStartRegistration.mode=existing",
		"--set", "global.envplane.firstStartRegistration.existingSecret=platform-first-start",
		"--set", "global.envplane.firstStartRegistration.cluster.id=management",
	)
	if strings.Contains(rendered, "kind: Secret\nmetadata:\n  name: platform-first-start") {
		t.Fatalf("existing first-start Secret must not be rendered by the chart:\n%s", rendered)
	}
	for _, expected := range []string{
		`name: "platform-first-start"`,
		"key: agent-registration-token",
		"key: runner-registration-token",
		"key: runner-project-config-token",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("existing first-start Secret reference missing %q:\n%s", expected, rendered)
		}
	}
}

func TestExternalDataAndImageDigestRenderWithoutProviderAssumptions(t *testing.T) {
	digest := "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	rendered := renderChildChart(t, "envplane-control-plane",
		"--set", "image.digest="+digest,
		"--set", "postgres.mode=external",
		"--set", "postgres.external.existingSecret=postgres-url",
		"--set", "redis.mode=external",
		"--set", "redis.external.existingSecret=redis-url",
	)
	for _, expected := range []string{
		"ghcr.io/envplane/api@" + digest,
		"name: \"postgres-url\"",
		"key: \"database-url\"",
		"name: \"redis-url\"",
		"key: \"redis-url\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("external data/digest render missing %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{
		"# Source: envplane/charts/envplane-control-plane/templates/postgres.yaml",
		"# Source: envplane/charts/envplane-control-plane/templates/redis.yaml",
		"alb.ingress.kubernetes.io",
		"external-dns.alpha.kubernetes.io",
	} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("external data render retained provider/internal assumption %q:\n%s", forbidden, rendered)
		}
	}
}

func TestInternalPostgresCanUseAnExistingPasswordSecret(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "envplane-control-plane.postgres.auth.existingSecret=platform-postgres-auth",
		"--set", "envplane-control-plane.postgres.auth.passwordKey=postgres-password",
	)
	for _, expected := range []string{
		"name: platform-postgres-auth",
		`key: "postgres-password"`,
		"name: wait-postgres",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("existing internal PostgreSQL Secret render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "kind: Secret\nmetadata:\n  name: envplane-control-plane-postgres") {
		t.Fatalf("chart must not create a PostgreSQL password Secret when an existing Secret is selected:\n%s", rendered)
	}
}

func TestLegacyDataEnabledFlagsRemainCompatibleWhenModeIsOmitted(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "envplane-control-plane.postgres.enabled=false",
		"--set", "envplane-control-plane.redis.enabled=false",
	)
	for _, forbidden := range []string{
		"# Source: envplane/charts/envplane-control-plane/templates/postgres.yaml",
		"# Source: envplane/charts/envplane-control-plane/templates/redis.yaml",
		"ENVPLANE_DATABASE_URL",
		"ENVPLANE_REDIS_URL",
	} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("legacy enabled=false must disable data resource %q:\n%s", forbidden, rendered)
		}
	}
}

func TestUmbrellaConditionallyOwnsSameClusterExecutionTargets(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
		"--set", "global.envplane.firstStartRegistration.mode=disabled",
		"--set", "envplane-agent.cluster.id=management-cluster",
		"--set", "envplane-agent.bootstrap.projectId=project-a",
		"--set", "envplane-runner.project.id=project-a",
		"--set", "envplane-runner.project.clusterId=management-cluster",
	)
	for _, expected := range []string{
		"# Source: envplane/charts/envplane-agent/templates/deployment.yaml",
		"# Source: envplane/charts/envplane-runner/templates/deployment.yaml",
		"name: envplane-agent",
		"name: envplane-runner",
		`value: "http://envplane-control-plane.envplane.svc:8080"`,
		`value: "management-cluster"`,
		`value: "project-a"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("enabled execution-target render missing %q:\n%s", expected, rendered)
		}
	}
}

func TestUmbrellaMigrationRenderPreservesLegacyFrontendSelector(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "envplane-control-plane.frontend.enabled=false",
		"--set", "envplane-control-plane.frontend.serviceName=envplane-control-plane-frontend",
		"--set", "envplane-frontend.fullnameOverride=envplane-control-plane-frontend",
		"--set", "envplane-frontend.legacyControlPlaneSelector=true",
	)
	for _, expected := range []string{
		"# Source: envplane/charts/envplane-frontend/templates/deployment.yaml",
		"name: envplane-control-plane-frontend",
		"app.kubernetes.io/name: envplane-control-plane",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("legacy frontend migration render missing %q:\n%s", expected, rendered)
		}
	}
}

func TestUmbrellaPackageVendorsDependencies(t *testing.T) {
	buildDependencies(t)
	temporary := t.TempDir()
	chartPath := umbrellaChartPath(t)
	cmd := exec.Command("helm", "package", chartPath, "--destination", temporary)
	cmd.Dir = chartPath
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("package umbrella: %v\n%s", err, output)
	}
	archive := filepath.Join(temporary, "envplane-"+umbrellaChartVersion(t)+".tgz")
	cmd = exec.Command("tar", "-tzf", archive)
	output, err = cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("list packaged umbrella: %v\n%s", err, output)
	}
	for _, expected := range []string{
		"envplane/charts/envplane-control-plane/Chart.yaml",
		"envplane/charts/envplane-frontend/Chart.yaml",
		"envplane/charts/envplane-agent/Chart.yaml",
		"envplane/charts/envplane-runner/Chart.yaml",
		"envplane/charts/envplane-webhook/Chart.yaml",
	} {
		if !strings.Contains(string(output), expected) {
			t.Fatalf("packaged umbrella does not vendor %q:\n%s", expected, output)
		}
	}
}

func TestUmbrellaDocumentsInstallerMigration(t *testing.T) {
	readme, err := os.ReadFile("../README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	for _, expected := range []string{
		"Migration from the installer Job chart",
		"helm upgrade envplane",
		"legacyControlPlaneSelector: true",
		"auth PVC",
		"wildcard\n   ClusterRole/ClusterRoleBinding",
	} {
		if !strings.Contains(string(readme), expected) {
			t.Fatalf("migration README missing %q", expected)
		}
	}
}

func TestUmbrellaReleaseContractPinsDirectChartSet(t *testing.T) {
	contract, err := os.ReadFile("../../../../release/0.3.0.yaml")
	if err != nil {
		t.Fatalf("read direct umbrella release contract: %v", err)
	}
	for _, expected := range []string{
		`version: "0.3.0"`,
		"umbrella: oci://ghcr.io/envplane/envplane:0.3.0",
		"controlPlane: oci://ghcr.io/envplane/envplane-control-plane:0.3.0",
		"frontend: oci://ghcr.io/envplane/envplane-frontend:0.2.0",
		"runner: oci://ghcr.io/envplane/envplane-runner:0.3.0",
		"installerImage: absent",
	} {
		if !strings.Contains(string(contract), expected) {
			t.Fatalf("direct umbrella release contract missing %q:\n%s", expected, contract)
		}
	}
}
