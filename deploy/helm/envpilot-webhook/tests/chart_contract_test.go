package tests

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestWebhookChartRendersStandaloneServiceWithSecretReferences(t *testing.T) {
	for _, path := range []string{"../Chart.yaml", "../values.yaml", "../templates/deployment.yaml", "../templates/service.yaml", "../templates/ingress.yaml", "../templates/secret.yaml"} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("required webhook chart file %s is missing: %v", path, err)
		}
	}
	command := exec.Command("helm", "template", "envpilot", "..", "--set", "secrets.existingSecret=envpilot-webhook-secrets")
	command.Dir = "."
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, output)
	}
	rendered := string(output)
	for _, expected := range []string{
		"kind: Deployment",
		"kind: Service",
		"name: envpilot-envpilot-webhook",
		`image: "ghcr.io/envpilot/webhook:0.1.0"`,
		"name: ENVPILOT_CONTROL_PLANE_TOKEN",
		"name: envpilot-webhook-secrets",
		"app.kubernetes.io/component: webhook",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("webhook chart render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "kind: Secret") {
		t.Fatal("existingSecret render must not create a plaintext Secret")
	}
}
