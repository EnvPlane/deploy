package tests

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

var buildUmbrellaDependencies sync.Once

func buildDependencies(t *testing.T) {
	t.Helper()
	buildUmbrellaDependencies.Do(func() {
		cmd := exec.Command("helm", "dependency", "build", "--skip-refresh", "..")
		cmd.Dir = "."
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("build umbrella dependencies: %v\n%s", err, output)
		}
	})
}

func renderUmbrella(t *testing.T, values ...string) string {
	t.Helper()
	buildDependencies(t)
	args := append([]string{"template", "envpilot", "..", "--namespace", "envpilot"}, values...)
	cmd := exec.Command("helm", args...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, output)
	}
	return string(output)
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
		"name: envpilot",
		"name: envpilot-control-plane",
		"name: envpilot-frontend",
		"name: envpilot-agent",
		"name: envpilot-runner",
		"condition: controlPlane.enabled",
		"condition: frontend.enabled",
		"condition: agent.enabled",
		"condition: runner.enabled",
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
		"../../../../cmd/envpilot-install",
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

func TestUmbrellaInjectsReleaseCompatibleAgentChartContract(t *testing.T) {
	chart, err := os.ReadFile("../Chart.yaml")
	if err != nil {
		t.Fatalf("read Chart.yaml: %v", err)
	}
	agentVersion := ""
	inAgentDependency := false
	for _, line := range strings.Split(string(chart), "\n") {
		if line == "  - name: envpilot-agent" {
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
		t.Fatal("envpilot-agent dependency version is missing")
	}
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatalf("read values.yaml: %v", err)
	}
	if !strings.Contains(string(values), `ref: "oci://ghcr.io/envpilot/envpilot-agent"`) || !strings.Contains(string(values), `version: "`+agentVersion+`"`) {
		t.Fatalf("umbrella values must carry the release-compatible Agent chart contract for %s:\n%s", agentVersion, values)
	}
	rendered := renderUmbrella(t)
	for _, expected := range []string{
		`name: ENVPILOT_AGENT_HELM_CHART_REF`,
		`value: "oci://ghcr.io/envpilot/envpilot-agent"`,
		`name: ENVPILOT_AGENT_HELM_CHART_VERSION`,
		`value: "` + agentVersion + `"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("active umbrella render missing Agent chart contract %q:\n%s", expected, rendered)
		}
	}
}

func TestUmbrellaE2EFixtureProfileOwnsRuntimeAndFixtureWorkloads(t *testing.T) {
	rendered := renderUmbrella(t, "--values", "../values-e2e-local.yaml")
	for _, expected := range []string{
		"# Source: envpilot/charts/envpilot-agent/templates/deployment.yaml",
		"# Source: envpilot/charts/envpilot-runner/templates/deployment.yaml",
		`name: "envpilot-e2e-base"`,
		`name: "envpilot-e2e-feature"`,
		"name: e2e-base-workload",
		"name: ENVPILOT_SAME_CLUSTER_FIXTURE_ENABLED",
		"name: ENVPILOT_SAME_CLUSTER_FIXTURE_RECOVERY_ENABLED",
		`value: "true"`,
		`value: "oci://ghcr.io/envpilot/envpilot-e2e-workload"`,
		`value: "envpilot-e2e-base"`,
		`value: "envpilot-e2e-feature"`,
		"agent-registration-token",
		"runner-registration-token",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("E2E fixture render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "ENVPILOT_SAME_CLUSTER_FIXTURE_ENABLED\n              value: \"false\"") {
		t.Fatalf("E2E fixture profile did not enable control-plane reconciliation:\n%s", rendered)
	}
}

func TestUmbrellaFixtureRecoveryIsExplicitlyOptIn(t *testing.T) {
	rendered := renderUmbrella(t, "--values", "../values-e2e-local.yaml", "--set", "global.envpilot.e2eFixture.recovery.enabled=false")
	if !strings.Contains(rendered, "name: ENVPILOT_SAME_CLUSTER_FIXTURE_RECOVERY_ENABLED\n              value: \"false\"") {
		t.Fatalf("fixture recovery must be disabled unless explicitly opted in:\n%s", rendered)
	}
	if strings.Contains(rendered, "runnerRegistrationToken") || strings.Contains(rendered, "agentRegistrationToken") {
		t.Fatalf("fixture render must not embed raw bootstrap credentials:\n%s", rendered)
	}
	if !strings.Contains(rendered, "name: ENVPILOT_SAME_CLUSTER_FIXTURE_CHART_VERSION\n              value: \"0.1.0\"") {
		t.Fatalf("fixture must pass the immutable OCI chart version to control-plane:\n%s", rendered)
	}
}

func TestUmbrellaRejectsFixtureWithoutChartManagedRuntime(t *testing.T) {
	buildDependencies(t)
	cmd := exec.Command("helm", "template", "envpilot", "..", "--set", "global.envpilot.e2eFixture.enabled=true")
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "requires managed or existing firstStartRegistration") {
		t.Fatalf("fixture without first-start runtime must fail, err=%v output=%s", err, output)
	}
}

func TestUmbrellaDirectlyOwnsDefaultWorkloads(t *testing.T) {
	rendered := renderUmbrella(t)
	for _, expected := range []string{
		"# Source: envpilot/charts/envpilot-control-plane/templates/deployment.yaml",
		"# Source: envpilot/charts/envpilot-frontend/templates/deployment.yaml",
		"name: envpilot-control-plane",
		"name: envpilot-frontend",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("umbrella render missing direct child workload %q:\n%s", expected, rendered)
		}
	}
	for _, forbidden := range []string{
		"name: envpilot-install",
		"ghcr.io/envpilot/install",
		"kubectl delete namespace",
		"kind: Ingress",
		"kind: HTTPRoute",
		"envpilot.local",
	} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("umbrella render contains retired installer behavior %q:\n%s", forbidden, rendered)
		}
	}
	for _, disabled := range []string{
		"# Source: envpilot/charts/envpilot-agent/templates/deployment.yaml",
		"# Source: envpilot/charts/envpilot-runner/templates/deployment.yaml",
	} {
		if strings.Contains(rendered, disabled) {
			t.Fatalf("Agent/Runner must remain opt-in by default; found %q", disabled)
		}
	}
	if !strings.Contains(rendered, "          envFrom:\n            - configMapRef:\n                name: \"envpilot-platform-dependency-status\"") {
		t.Fatalf("platform dependency status must be injected into the API container:\n%s", rendered)
	}
	if strings.Contains(rendered, "      envFrom:\n        - configMapRef:") {
		t.Fatalf("platform dependency status must not be rendered at PodSpec scope:\n%s", rendered)
	}
}

func TestUmbrellaRegistrySecretPropagatesToEveryRuntimePod(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
	)
	for _, expected := range []string{
		"# Source: envpilot/templates/registry-preflight-job.yaml",
		"# Source: envpilot/charts/envpilot-control-plane/templates/deployment.yaml",
		"# Source: envpilot/charts/envpilot-frontend/templates/deployment.yaml",
		"# Source: envpilot/charts/envpilot-agent/templates/deployment.yaml",
		"# Source: envpilot/charts/envpilot-runner/templates/deployment.yaml",
		"name: registry-credentials",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("private registry render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "dockerconfigjson:") || strings.Contains(rendered, "registry-auth:") {
		t.Fatalf("rendered chart must contain only registry Secret references, not credential data:\n%s", rendered)
	}

	cmd := exec.Command("helm", "template", "envpilot", "..", "--set", "global.envpilot.registry.mode=existing")
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err == nil || (!strings.Contains(string(output), "global.envpilot.registry.existingSecret is required") && !strings.Contains(string(output), "existingSecret")) {
		t.Fatalf("missing registry Secret reference must fail early, err=%v output=%s", err, output)
	}
}

func TestChildChartsShareExplicitImageContract(t *testing.T) {
	components := []string{
		"envpilot-control-plane",
		"envpilot-frontend",
		"envpilot-agent",
		"envpilot-runner",
	}

	args := []string{
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
	}
	for _, component := range components {
		args = append(args,
			"--set", component+".image.repository=registry.example.internal/envpilot/"+strings.TrimPrefix(component, "envpilot-"),
			"--set", component+".image.tag=build-20260731",
			"--set", component+".image.digest=",
			"--set", component+".image.pullPolicy=Always",
			"--set", component+".image.sourceRevision=abcdef123456",
			"--set", component+".image.release=2026.07.31",
			"--set", component+".imagePullSecrets[0].name=private-registry",
		)
	}
	rendered := renderUmbrella(t, args...)
	for _, component := range components {
		imageName := strings.TrimPrefix(component, "envpilot-")
		for _, expected := range []string{
			`image: "registry.example.internal/envpilot/` + imageName + `:build-20260731"`,
			"imagePullPolicy: Always",
			"envpilot.io/source-revision: abcdef123456",
			"envpilot.io/release: 2026.07.31",
		} {
			if !strings.Contains(rendered, expected) {
				t.Fatalf("%s tag/private-registry render missing %q:\n%s", component, expected, rendered)
			}
		}
	}
	if count := strings.Count(rendered, "name: private-registry"); count < len(components) {
		t.Fatalf("private registry pull secret was not rendered for every child: count=%d\n%s", count, rendered)
	}

	const digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	digestArgs := []string{"--set", "agent.enabled=true", "--set", "runner.enabled=true"}
	for _, component := range components {
		digestArgs = append(digestArgs,
			"--set", component+".image.repository=registry.example.internal/envpilot/"+strings.TrimPrefix(component, "envpilot-"),
			"--set", component+".image.tag=must-not-be-rendered",
			"--set", component+".image.digest="+digest,
		)
	}
	digestRender := renderUmbrella(t, digestArgs...)
	for _, component := range components {
		imageName := strings.TrimPrefix(component, "envpilot-")
		expected := `image: "registry.example.internal/envpilot/` + imageName + `@` + digest + `"`
		if !strings.Contains(digestRender, expected) {
			t.Fatalf("%s digest render missing %q:\n%s", component, expected, digestRender)
		}
	}
	for _, component := range components {
		imageName := strings.TrimPrefix(component, "envpilot-")
		forbidden := `image: "registry.example.internal/envpilot/` + imageName + `:must-not-be-rendered"`
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
	for _, component := range []string{"envpilot-control-plane", "envpilot-frontend", "envpilot-agent", "envpilot-runner"} {
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
			args := []string{
				"template", "envpilot", "..",
				"--set", component + ".image.tag=" + invalid.value,
				"--set", component + ".image.digest=",
			}
			if component == "envpilot-agent" {
				args = append(args, "--set", "agent.enabled=true")
			}
			if component == "envpilot-runner" {
				args = append(args, "--set", "runner.enabled=true")
			}
			cmd := exec.Command("helm", args...)
			cmd.Dir = "."
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
		"--set", "access.ingress.host=envpilot.example.internal",
		"--set", "access.ingress.className=shared-ingress",
		"--set", "access.ingress.annotations.example\\.io/owner=platform",
	)
	for _, expected := range []string{
		"kind: Ingress",
		"host: \"envpilot.example.internal\"",
		"ingressClassName: \"shared-ingress\"",
		"example.io/owner: platform",
		"name: envpilot-control-plane",
		"name: envpilot-frontend",
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
		"--set", "access.gateway.hostnames[0]=envpilot.example.internal",
	)
	for _, expected := range []string{
		"apiVersion: gateway.networking.k8s.io/v1",
		"kind: HTTPRoute",
		"name: \"shared-gateway\"",
		"namespace: \"gateway-system\"",
		"sectionName: \"https\"",
		"- envpilot.example.internal",
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
				"ENVPILOT_PLATFORM_INGRESS_MODE: \"disabled\"",
			},
			forbidden: []string{"kind: Ingress", "kind: HTTPRoute", "alb.ingress.kubernetes.io"},
		},
		{
			name:    "nginx ingress",
			profile: "nginx-ingress.yaml",
			expected: []string{
				"kind: Ingress",
				"ingressClassName: \"nginx\"",
				"ENVPILOT_PLATFORM_INGRESS_PROVIDER: \"nginx\"",
			},
			forbidden: []string{"alb.ingress.kubernetes.io", "kind: HTTPRoute"},
		},
		{
			name:    "AWS ALB",
			profile: "aws-alb.yaml",
			expected: []string{
				"ingressClassName: \"alb\"",
				"alb.ingress.kubernetes.io/scheme: internet-facing",
				"ENVPILOT_PLATFORM_DNS_PROVIDER: \"external-dns\"",
			},
			forbidden: []string{"kind: HTTPRoute"},
		},
		{
			name:    "Gateway API",
			profile: "gateway-api.yaml",
			expected: []string{
				"kind: HTTPRoute",
				"name: \"shared-gateway\"",
				"ENVPILOT_PLATFORM_INGRESS_PROVIDER: \"gateway-api\"",
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
				"name: \"envpilot-postgres-url\"",
				"name: \"envpilot-redis-url\"",
			},
			forbidden: []string{
				"# Source: envpilot/charts/envpilot-control-plane/templates/postgres.yaml",
				"# Source: envpilot/charts/envpilot-control-plane/templates/redis.yaml",
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			rendered := renderUmbrella(t, "--values", filepath.Join("..", "profiles", tc.profile))
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
		"--set", "platformDependencies.storage.ownership=envpilot",
		"--set", "platformDependencies.storage.managed.chartRef=oci://ghcr.io/example/local-path",
		"--set", "platformDependencies.storage.managed.version=1.0.0",
		"--set", "platformDependencies.storage.managed.releaseName=local-path",
	)
	for _, expected := range []string{
		"name: envpilot-platform-dependency-status",
		"ENVPILOT_PLATFORM_INGRESS_PROVIDER: \"nginx\"",
		"ENVPILOT_PLATFORM_INGRESS_REFERENCE: \"ingress-nginx\"",
		"ENVPILOT_PLATFORM_INGRESS_OWNERSHIP: \"external\"",
		"ENVPILOT_PLATFORM_INGRESS_STATE: \"detected\"",
		"ENVPILOT_PLATFORM_STORAGE_PROVIDER: \"local-path\"",
		"ENVPILOT_PLATFORM_STORAGE_STATE: \"managed\"",
		"configMapRef:",
		"name: \"envpilot-platform-dependency-status\"",
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
		"--set", "access.ingress.host=envpilot.example.test",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envpilot-control-plane-platform-dependency-status-reader",
		"resources: [\"configmaps\"]",
		"verbs: [\"get\", \"watch\"]",
		"name: ENVPILOT_PLATFORM_DEPENDENCY_STATUS_CONFIG_MAP",
		"value: \"envpilot-platform-dependency-reconciler-status-r1\"",
		"name: ENVPILOT_PLATFORM_DEPENDENCY_STATUS_STALE_AFTER_SECONDS",
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
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
		"--set", "platformDependencyReconciler.cleanupManagedOnUninstall=true",
	)
	for _, expected := range []string{
		"\"helm.sh/hook\": post-install,post-upgrade",
		"\"helm.sh/hook\": pre-delete",
		"resources: [\"ingressclasses\"]",
		"resources: [\"storageclasses\"]",
		"app.kubernetes.io/component: platform-reconciler",
		"ENVPILOT_RECONCILE_CONFIG_JSON",
		"name: HOME\n              value: /tmp/envpilot-home",
		"name: XDG_CACHE_HOME\n              value: /tmp/envpilot-home/.cache",
		"mountPath: /tmp",
		"\"helm.sh/hook-delete-policy\": before-hook-creation,hook-succeeded,hook-failed",
		"app.kubernetes.io/managed-by: Helm",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("platform reconciler contract missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "resources: [\"deployments\", \"pods\"]") || strings.Contains(rendered, "helm.sh/hook: post-install") {
		t.Fatal("platform reconciler must not own EnvPilot core workloads")
	}
}

func TestNginxCleanInstallHooksAreActionAwareAndFailureSafe(t *testing.T) {
	existing := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=nginx",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
	)
	if strings.Contains(existing, "platform-reconciler-namespaces") {
		t.Fatalf("existing nginx must not render namespace setup hook:\n%s", existing)
	}
	if !strings.Contains(existing, "name: envpilot-platform-reconciler\n") ||
		!strings.Contains(existing, "\"helm.sh/hook-delete-policy\": before-hook-creation,hook-succeeded,hook-failed") {
		t.Fatalf("existing nginx must render a self-cleaning reconciler hook:\n%s", existing)
	}

	managed := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envpilot.example.test",
		"--set", "access.ingress.className=nginx",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envpilot-platform-reconciler-namespaces",
		"name: ENVPILOT_RECONCILE_ACTION\n              value: ensure-namespaces",
		"name: ENVPILOT_RECONCILE_PROVIDER_NAMESPACES",
		"\"helm.sh/hook-delete-policy\": before-hook-creation,hook-succeeded,hook-failed",
	} {
		if !strings.Contains(managed, expected) {
			t.Fatalf("managed nginx clean-install hook contract missing %q:\n%s", expected, managed)
		}
	}
	if strings.Contains(managed, "ENVPILOT_RECONCILE_CONFIG_JSON\n              value:") {
		t.Fatalf("namespace setup must not receive an inline dependency config:\n%s", managed)
	}
}

func TestPlatformReconcilerStatusConfigMapIsHelmOwnedAndWriteScoped(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envpilot-platform-dependency-reconciler-status-r1",
		"status.json: \"\"",
		"resourceNames: [\"envpilot-platform-dependency-reconciler\", \"envpilot-platform-dependency-reconciler-status-r1\"]",
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
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envpilot-platform-dependency-reconciler-status-r1",
		"value: \"envpilot-platform-dependency-reconciler-status-r1\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("revision-scoped reconciler status contract missing %q:\\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "name: envpilot-platform-dependency-reconciler-status\\n") {
		t.Fatalf("status ConfigMap must not retain an unversioned name:\\n%s", rendered)
	}

	compatibilityTemplate, err := os.ReadFile("../templates/remote-cluster-compatibility-configmap.yaml")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(compatibilityTemplate), "envpilot.remoteClusterCompatibilityConfigMapName") ||
		strings.Contains(string(compatibilityTemplate), "name: {{ .Release.Name }}-remote-cluster-compatibility") {
		t.Fatalf("immutable compatibility map must use the revision-scoped helper:\\n%s", compatibilityTemplate)
	}

	child := exec.Command("helm", "template", "envpilot", "../../envpilot-control-plane", "--namespace", "envpilot",
		"--set", "global.envpilot.remoteClusterReconciler.enabled=true",
		"--set", "rbac.remoteClusterReconciler.enabled=true")
	child.Dir = "."
	childRendered, err := child.CombinedOutput()
	if err != nil {
		t.Fatalf("render control-plane compatibility consumer: %v\\n%s", err, childRendered)
	}
	for _, expected := range []string{"name: \"envpilot-remote-cluster-compatibility-r1\""} {
		if !strings.Contains(string(childRendered), expected) {
			t.Fatalf("control-plane must consume revision-scoped compatibility map %q:\\n%s", expected, childRendered)
		}
	}
}

func TestPlatformReconcilerSupportsPrivateRegistryPullSecrets(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencyReconciler.imagePullSecrets[0].name=ghcr-envpilot",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
	)
	for _, expected := range []string{
		"name: envpilot-platform-reconciler",
		"imagePullSecrets:\n        - name: ghcr-envpilot",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("platform reconciler private-registry render missing %q:\n%s", expected, rendered)
		}
	}
}

func TestPlatformReconcilerPrerequisitesRunBeforeTheGateJob(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envpilot.example.test",
		"--set", "access.ingress.className=nginx",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"name: envpilot-platform-dependency-reconciler\n  namespace: envpilot\n  labels:\n    app.kubernetes.io/name: envpilot",
		"name: envpilot-platform-reconciler\n  namespace: envpilot\n  labels:\n    app.kubernetes.io/name: envpilot",
		"name: envpilot-platform-reconciler-namespaces\n  namespace: envpilot\n  annotations:\n    \"helm.sh/hook\": post-install,post-upgrade\n    \"helm.sh/hook-weight\": \"-30\"",
		"name: envpilot-platform-reconciler\n  namespace: envpilot\n  annotations:\n    \"helm.sh/hook\": post-install,post-upgrade\n    \"helm.sh/hook-weight\": \"10\"",
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

func TestPlatformReconcilerRequiresRegistryCredentialsBeforeHooks(t *testing.T) {
	cmd := exec.Command("helm", "template", "envpilot", "..",
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
	)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "platformDependencyReconciler requires") {
		t.Fatalf("reconciler must fail with an actionable registry requirement, err=%v output=%s", err, output)
	}
}

func TestPlatformReconcilerCleanupIsBoundedAndFailureSafe(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "platformDependencyReconciler.cleanupManagedOnUninstall=true",
		"--set", "platformDependencies.ingress.mode=existing",
		"--set", "platformDependencies.ingress.existingClassName=ingress-nginx",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
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
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
		"--set", "platformDependencies.ingress.mode=managed",
		"--set", "platformDependencies.ingress.provider=nginx",
		"--set", "platformDependencies.ingress.ownership=envpilot",
		"--set", "platformDependencies.ingress.managed.chartRef=https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-4.11.0/ingress-nginx-4.11.0.tgz",
		"--set", "platformDependencies.ingress.managed.version=4.11.0",
		"--set", "platformDependencies.ingress.managed.releaseName=envpilot-ingress-nginx",
		"--set", "platformDependencies.ingress.managed.smoke.serviceName=envpilot-frontend",
		"--set", "platformDependencies.ingress.managed.smoke.namespace=envpilot",
		"--set", "platformDependencies.ingress.managed.smoke.port=3000",
		"--set", "platformDependencies.ingress.managed.smoke.host=envpilot.example.test",
	)
	for _, expected := range []string{"resources: [\"services\", \"endpoints\"]", "resources: [\"ingresses\"]", "ENVPILOT_RECONCILE_ACTION", "envpilot.example.test"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("managed ingress contract missing %q:\n%s", expected, rendered)
		}
	}
}

func TestIngressAccessProfileAutomaticallyReconcilesMissingNginxController(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envpilot.example.test",
		"--set", "access.ingress.className=nginx",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"kind: Ingress",
		"ingressClassName: \"nginx\"",
		"kind: Job",
		"name: envpilot-platform-reconciler",
		"ENVPILOT_RECONCILE_CONFIG_JSON",
		"mode\\\":\\\"auto\\\"",
		"provider\\\":\\\"nginx\\\"",
		"helm-chart-4.11.0/ingress-nginx-4.11.0.tgz",
		"releaseName\\\":\\\"envpilot-ingress-nginx\\\"",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("ingress access profile missing automatic controller reconciliation %q:\n%s", expected, rendered)
		}
	}
}

func TestIngressAccessProfileGrantsOnlyScopedProviderInstallerPermissions(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "access.mode=ingress",
		"--set", "access.ingress.host=envpilot.example.test",
		"--set", "access.ingress.className=nginx",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
	)
	for _, expected := range []string{
		"resources: [\"namespaces\"]\n    verbs: [\"get\", \"create\"]",
		"resources: [\"clusterroles\", \"clusterrolebindings\"]",
		"resources: [\"validatingwebhookconfigurations\"]",
		"name: envpilot-platform-reconciler-ingress-installer",
		"namespace: ingress-nginx",
		"resources: [\"configmaps\", \"endpoints\", \"events\", \"pods\", \"secrets\", \"serviceaccounts\", \"services\"]",
		"name: envpilot-platform-reconciler-namespaces",
		"ENVPILOT_RECONCILE_PROVIDER_NAMESPACES",
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
		"--set", "access.ingress.host=envpilot.example.test",
		"--set", "access.ingress.className=alb",
	)
	if strings.Contains(rendered, "platform-reconciler-discovery") || strings.Contains(rendered, "kind: Job\nmetadata:\n  name: envpilot-platform-reconciler") {
		t.Fatalf("non-nginx ingress class must not implicitly install a provider:\n%s", rendered)
	}
}

func TestManagedExternalDNSRendersScopedContract(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
		"--set", "platformDependencies.dns.mode=managed",
		"--set", "platformDependencies.dns.provider=external-dns",
		"--set", "platformDependencies.dns.ownership=envpilot",
		"--set", "platformDependencies.dns.credentials.existingSecret=dns-credentials",
		"--set", "platformDependencies.dns.domainFilters[0]=example.test",
		"--set", "platformDependencies.dns.ownershipId=envpilot",
		"--set", "platformDependencies.dns.policy=sync",
		"--set", "platformDependencies.dns.managed.chartRef=oci://ghcr.io/kubernetes-sigs/external-dns/external-dns",
		"--set", "platformDependencies.dns.managed.version=1.15.0",
		"--set", "platformDependencies.dns.managed.releaseName=envpilot-external-dns",
	)
	for _, expected := range []string{"resources: [\"deployments\"]", "resources: [\"secrets\"]", "dns-credentials", "example.test", "envpilot-external-dns"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("managed DNS contract missing %q:\n%s", expected, rendered)
		}
	}
}

func TestManagedLocalPathStorageRendersSmokeContract(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
		"--set", "platformDependencies.storage.mode=managed",
		"--set", "platformDependencies.storage.provider=local-path-provisioner",
		"--set", "platformDependencies.storage.ownership=envpilot",
		"--set", "platformDependencies.storage.managed.chartRef=oci://ghcr.io/rancher/local-path-provisioner",
		"--set", "platformDependencies.storage.managed.version=0.0.28",
		"--set", "platformDependencies.storage.managed.releaseName=envpilot-local-path",
	)
	for _, expected := range []string{"resources: [\"storageclasses\"]", "resources: [\"csidrivers\"]", "resources: [\"persistentvolumeclaims\"]", "local-path-provisioner", "envpilot-local-path"} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("managed storage contract missing %q:\n%s", expected, rendered)
		}
	}
	gated := renderUmbrella(t,
		"--set", "platformDependencyReconciler.enabled=true",
		"--set", "global.envpilot.registry.mode=existing",
		"--set", "global.envpilot.registry.existingSecret=registry-credentials",
		"--set", "platformDependencies.storage.mode=existing",
		"--set", "platformDependencies.storage.existingClassName=standard",
		"--set", "platformDependencies.storage.provider=local-path-provisioner",
	)
	if !strings.Contains(gated, "ENVPILOT_RECONCILE_GATE_STORAGE") {
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
		"duplicate rendered resource", "namespace leakage", "envpilot-install", "cluster-admin",
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
		"helm upgrade", "helm rollback", "helm uninstall", "ENVPILOT_E2E_EXISTING_RESOURCES",
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

func TestPublishedConfigMapUpgradeE2ECoversNMinus1RollbackAndUninstall(t *testing.T) {
	script, err := os.ReadFile("../../../../scripts/published-configmap-upgrade-e2e.sh")
	if err != nil {
		t.Fatal(err)
	}
	contents := string(script)
	for _, expected := range []string{
		"ENVPILOT_CONFIGMAP_E2E_CHART_N_MINUS_1",
		"ENVPILOT_CONFIGMAP_E2E_CHART_N",
		"--server-side=true",
		"--field-manager=platform-reconciler",
		"platform-dependency-reconciler-status-r",
		"remote-cluster-compatibility-r",
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
	contents := string(docs)
	for _, expected := range []string{
		"helm upgrade --install envpilot oci://ghcr.io/envpilot/envpilot",
		"--version <published-umbrella-version>", "--namespace envpilot", "--values values.yaml",
		"auto", "managed", "existing", "disabled", "Kubernetes 1.26",
		"Private registry", "minikube-", "not required",
	} {
		if !strings.Contains(contents, expected) {
			t.Fatalf("installation docs missing %q", expected)
		}
	}
	for _, forbidden := range []string{"helm install envpilot-control-plane", "installer Job is required"} {
		if strings.Contains(contents, forbidden) {
			t.Fatalf("installation docs contain unsupported production path %q", forbidden)
		}
	}
}

func TestAllComponentRenderMeetsRestrictedPodSecurityBaseline(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
		"--set", "global.envpilot.firstStartRegistration.mode=managed",
		"--set", "global.envpilot.firstStartRegistration.cluster.id=management",
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
	for _, args := range [][]string{
		{"template", "envpilot", "..", "--set", "access.mode=not-a-mode"},
		{"template", "envpilot", "..", "--set", "access.mode=ingress"},
		{"template", "envpilot", "..", "--set", "access.mode=gateway"},
		{"template", "envpilot", "..", "--set", "global.envpilot.firstStartRegistration.mode=existing"},
	} {
		cmd := exec.Command("helm", args...)
		cmd.Dir = "."
		if output, err := cmd.CombinedOutput(); err == nil {
			t.Fatalf("invalid values unexpectedly passed schema: %v\n%s", args, output)
		}
	}
}

func TestFirstStartRegistrationRendersManagedSecretAndSameClusterIdentities(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "agent.enabled=true",
		"--set", "runner.enabled=true",
		"--set", "global.envpilot.firstStartRegistration.mode=managed",
		"--set", "global.envpilot.firstStartRegistration.cluster.id=management",
	)
	for _, expected := range []string{
		"name: envpilot-first-start-registration",
		"agent-registration-token:",
		"runner-registration-token:",
		"runner-project-config-token:",
		"name: ENVPILOT_SAME_CLUSTER_REGISTRATION_ENABLED",
		"name: ENVPILOT_SAME_CLUSTER_AGENT_REGISTRATION_TOKEN",
		"name: ENVPILOT_SAME_CLUSTER_RUNNER_REGISTRATION_TOKEN",
		"name: ENVPILOT_AGENT_REGISTRATION_TOKEN",
		"name: ENVPILOT_RUNNER_REGISTRATION_TOKEN",
		"name: ENVPILOT_PROJECT_CONFIG_TOKEN",
		`value: "management"`,
		`value: "envpilot"`,
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("first-start render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "envpilot-agent-install-check") {
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
		"--set", "global.envpilot.firstStartRegistration.mode=existing",
		"--set", "global.envpilot.firstStartRegistration.existingSecret=platform-first-start",
		"--set", "global.envpilot.firstStartRegistration.cluster.id=management",
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
	rendered := renderUmbrella(t,
		"--set", "envpilot-control-plane.image.digest="+digest,
		"--set", "envpilot-control-plane.postgres.mode=external",
		"--set", "envpilot-control-plane.postgres.external.existingSecret=postgres-url",
		"--set", "envpilot-control-plane.redis.mode=external",
		"--set", "envpilot-control-plane.redis.external.existingSecret=redis-url",
	)
	for _, expected := range []string{
		"ghcr.io/envpilot/api@" + digest,
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
		"# Source: envpilot/charts/envpilot-control-plane/templates/postgres.yaml",
		"# Source: envpilot/charts/envpilot-control-plane/templates/redis.yaml",
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
		"--set", "envpilot-control-plane.postgres.auth.existingSecret=platform-postgres-auth",
		"--set", "envpilot-control-plane.postgres.auth.passwordKey=postgres-password",
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
	if strings.Contains(rendered, "# Source: envpilot/charts/envpilot-control-plane/templates/secret.yaml") {
		t.Fatalf("chart must not create a PostgreSQL password Secret when an existing Secret is selected:\n%s", rendered)
	}
}

func TestLegacyDataEnabledFlagsRemainCompatibleWhenModeIsOmitted(t *testing.T) {
	rendered := renderUmbrella(t,
		"--set", "envpilot-control-plane.postgres.enabled=false",
		"--set", "envpilot-control-plane.redis.enabled=false",
	)
	for _, forbidden := range []string{
		"# Source: envpilot/charts/envpilot-control-plane/templates/postgres.yaml",
		"# Source: envpilot/charts/envpilot-control-plane/templates/redis.yaml",
		"ENVPILOT_DATABASE_URL",
		"ENVPILOT_REDIS_URL",
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
		"--set", "envpilot-agent.cluster.id=management-cluster",
		"--set", "envpilot-agent.bootstrap.projectId=project-a",
		"--set", "envpilot-runner.project.id=project-a",
		"--set", "envpilot-runner.project.clusterId=management-cluster",
	)
	for _, expected := range []string{
		"# Source: envpilot/charts/envpilot-agent/templates/deployment.yaml",
		"# Source: envpilot/charts/envpilot-runner/templates/deployment.yaml",
		"name: envpilot-agent",
		"name: envpilot-runner",
		`value: "http://envpilot-control-plane.envpilot.svc:8080"`,
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
		"--set", "envpilot-control-plane.frontend.enabled=false",
		"--set", "envpilot-control-plane.frontend.serviceName=envpilot-control-plane-frontend",
		"--set", "envpilot-frontend.fullnameOverride=envpilot-control-plane-frontend",
		"--set", "envpilot-frontend.legacyControlPlaneSelector=true",
	)
	for _, expected := range []string{
		"# Source: envpilot/charts/envpilot-frontend/templates/deployment.yaml",
		"name: envpilot-control-plane-frontend",
		"app.kubernetes.io/name: envpilot-control-plane",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("legacy frontend migration render missing %q:\n%s", expected, rendered)
		}
	}
}

func TestUmbrellaPackageVendorsDependencies(t *testing.T) {
	buildDependencies(t)
	temporary := t.TempDir()
	cmd := exec.Command("helm", "package", "..", "--destination", temporary)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("package umbrella: %v\n%s", err, output)
	}
	archive := filepath.Join(temporary, "envpilot-"+umbrellaChartVersion(t)+".tgz")
	cmd = exec.Command("tar", "-tzf", archive)
	output, err = cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("list packaged umbrella: %v\n%s", err, output)
	}
	for _, expected := range []string{
		"envpilot/charts/envpilot-control-plane/Chart.yaml",
		"envpilot/charts/envpilot-frontend/Chart.yaml",
		"envpilot/charts/envpilot-agent/Chart.yaml",
		"envpilot/charts/envpilot-runner/Chart.yaml",
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
		"helm upgrade envpilot",
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
		"umbrella: oci://ghcr.io/envpilot/envpilot:0.3.0",
		"controlPlane: oci://ghcr.io/envpilot/envpilot-control-plane:0.3.0",
		"frontend: oci://ghcr.io/envpilot/envpilot-frontend:0.2.0",
		"runner: oci://ghcr.io/envpilot/envpilot-runner:0.3.0",
		"installerImage: absent",
	} {
		if !strings.Contains(string(contract), expected) {
			t.Fatalf("direct umbrella release contract missing %q:\n%s", expected, contract)
		}
	}
}
