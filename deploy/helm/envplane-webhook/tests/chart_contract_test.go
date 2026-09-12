package tests

import (
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

const latestLegacyFallbackDeadline = "2027-03-12T23:59:59Z"

func TestLegacyFallbackDeadlineHasFixedRemovalBound(t *testing.T) {
	values, err := os.ReadFile("../values.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var configured string
	for _, line := range strings.Split(string(values), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "legacyFallbackUntil:") {
			configured = strings.Trim(strings.TrimSpace(strings.TrimPrefix(line, "legacyFallbackUntil:")), "\"")
			break
		}
	}
	deadline, err := time.Parse(time.RFC3339, configured)
	if err != nil {
		t.Fatalf("legacyFallbackUntil must be RFC3339: %q: %v", configured, err)
	}
	maximum, err := time.Parse(time.RFC3339, latestLegacyFallbackDeadline)
	if err != nil {
		t.Fatal(err)
	}
	if deadline.After(maximum) {
		t.Fatalf("legacyFallbackUntil %s exceeds the approved removal bound %s; EP-WHR-007 requires an explicit removal-plan review", deadline.Format(time.RFC3339), maximum.Format(time.RFC3339))
	}
}

func TestWebhookChartRendersStandaloneServiceWithSecretReferences(t *testing.T) {
	for _, path := range []string{"../Chart.yaml", "../values.yaml", "../templates/deployment.yaml", "../templates/service.yaml", "../templates/ingress.yaml", "../templates/secret.yaml"} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("required webhook chart file %s is missing: %v", path, err)
		}
	}
	command := exec.Command("helm", "template", "envplane", "..", "--set", "secrets.existingSecret=envplane-webhook-secrets")
	command.Dir = "."
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("helm template failed: %v\n%s", err, output)
	}
	rendered := string(output)
	for _, expected := range []string{
		"kind: Deployment",
		"kind: Service",
		"name: envplane-envplane-webhook",
		`image: "ghcr.io/envplane/webhook:0.1.0"`,
		"name: ENVPLANE_WEBHOOK_RECEIVER_TOKEN",
		"name: \"envplane-webhook-receiver\"",
		"app.kubernetes.io/component: webhook",
	} {
		if !strings.Contains(rendered, expected) {
			t.Fatalf("webhook chart render missing %q:\n%s", expected, rendered)
		}
	}
	if strings.Contains(rendered, "kind: Secret") {
		t.Fatal("existingSecret render must not create a plaintext Secret")
	}
	for _, forbidden := range []string{"ENVPLANE_CONTROL_PLANE_TOKEN", "ENVPLANE_GITHUB_WEBHOOK_SECRET", "ENVPLANE_GITLAB_WEBHOOK_TOKEN"} {
		if strings.Contains(rendered, forbidden) {
			t.Fatalf("webhook receiver render must not expose signing or legacy control-plane credential %q", forbidden)
		}
	}
}
