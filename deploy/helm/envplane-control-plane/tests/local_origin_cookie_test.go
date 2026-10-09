package tests

import (
	"os/exec"
	"strings"
	"testing"
)

func TestExternalRelayLocalHTTPCookieProfile(t *testing.T) {
	for _, origin := range []string{"http://envplane.local", "http://localhost:3000", "http://127.0.0.1:3000", "http://[::1]:3000"} {
		rendered := renderControlPlaneChart(t, "--set", "publicURL="+origin, "--set-string", "env.ENVPLANE_PUBLIC_URL_ALLOW_HTTP_LOCAL_DEVELOPMENT=true")
		if !strings.Contains(rendered, "name: ENVPLANE_OAUTH_COOKIE_SECURE\n              value: \"false\"") {
			t.Fatalf("local relay cookies not configured for %s", origin)
		}
	}
	for _, origin := range []string{"https://envplane.local", "https://customer.example", "http://customer.example"} {
		rendered := renderControlPlaneChart(t, "--set", "publicURL="+origin, "--set-string", "env.ENVPLANE_PUBLIC_URL_ALLOW_HTTP_LOCAL_DEVELOPMENT=true")
		if strings.Contains(rendered, "name: ENVPLANE_OAUTH_COOKIE_SECURE\n              value: \"false\"") {
			t.Fatal("external/HTTPS cookie security weakened")
		}
	}
	cmd := exec.Command("helm", "template", "envplane", controlPlaneChartPath(t), "--set", "publicURL=http://envplane.local", "--set-string", "env.ENVPLANE_PUBLIC_URL_ALLOW_HTTP_LOCAL_DEVELOPMENT=true", "--set-string", "env.ENVPLANE_OAUTH_COOKIE_SECURE=true")
	if output, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(output), "local HTTP publicURL cannot use Secure cookies") {
		t.Fatal("contradictory cookie profile accepted")
	}
}
