package tests

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

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
		"range $key, $value := .Values.env",
		"ENVPILOT_DATABASE_URL",
		"ENVPILOT_REDIS_URL",
		"mountPath: /var/lib/envpilot",
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
		"ENVPILOT_DATA_DIR",
		"ENVPILOT_GITOPS_DIR",
		"ENVPILOT_POSTGRES_MIGRATIONS_DIR",
		"ENVPILOT_DEPENDENCY_WAIT_TIMEOUT_SECONDS",
		`ENVPILOT_GITHUB_WEBHOOK_DEBUG_PAYLOAD_LOG: "false"`,
		"domain: envpilot.bethunder.ca",
		"certManager:",
		"postgres:",
		"redis:",
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

func TestControlPlaneChartRendersHTTPSIngressForFrontendAndAPI(t *testing.T) {
	rendered := renderControlPlaneChart(t,
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
		`value: "redis://envpilot-control-plane-redis:6379/0"`,
		`value: "/var/lib/envpilot/migrations/postgres"`,
		"--appendonly",
		"volumeClaimTemplates:",
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
		"repository: ghcr.io/envpilot/frontend",
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

func renderControlPlaneChart(t *testing.T, args ...string) string {
	t.Helper()
	commandArgs := append([]string{"template", "envpilot", ".."}, args...)
	cmd := exec.Command("helm", commandArgs...)
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, string(output))
	}
	return string(output)
}
