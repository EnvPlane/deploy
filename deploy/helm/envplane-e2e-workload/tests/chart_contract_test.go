package tests

import (
	"os/exec"
	"strings"
	"testing"
)

func TestE2EWorkloadUsesTheStandardImageContract(t *testing.T) {
	render := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("helm", append([]string{"template", "e2e", ".."}, args...)...)
		cmd.Dir = "."
		output, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("helm template failed: %v\n%s", err, output)
		}
		return string(output)
	}

	tagRender := render(
		"--set", "image.repository=registry.example.internal/envplane/e2e",
		"--set", "image.tag=build-20260731",
		"--set", "image.pullPolicy=Always",
		"--set", "image.sourceRevision=abcdef123456",
		"--set", "image.release=2026.07.31",
		"--set", "imagePullSecrets[0].name=private-registry",
	)
	for _, expected := range []string{
		`image: "registry.example.internal/envplane/e2e:build-20260731"`,
		"imagePullPolicy: Always",
		"name: private-registry",
		"envplane.io/source-revision: abcdef123456",
		"envplane.io/release: 2026.07.31",
	} {
		if !strings.Contains(tagRender, expected) {
			t.Fatalf("tag/private-registry render missing %q:\n%s", expected, tagRender)
		}
	}

	const digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	digestRender := render(
		"--set", "image.repository=registry.example.internal/envplane/e2e",
		"--set", "image.tag=must-not-be-rendered",
		"--set", "image.digest="+digest,
	)
	if !strings.Contains(digestRender, `image: "registry.example.internal/envplane/e2e@`+digest+`"`) ||
		strings.Contains(digestRender, `image: "registry.example.internal/envplane/e2e:must-not-be-rendered"`) {
		t.Fatalf("digest must take precedence over tag:\n%s", digestRender)
	}
}

func TestE2EWorkloadRejectsLatest(t *testing.T) {
	cmd := exec.Command("helm", "template", "e2e", "..", "--set", "image.tag=latest")
	cmd.Dir = "."
	output, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(output), "image.tag must not be latest") {
		t.Fatalf("chart accepted latest, err=%v output=%s", err, output)
	}
}
