package tests

import (
	"fmt"
	"strings"
	"testing"
)

func TestAgentFluxDiscoveryRuntimeMatchesRBAC(t *testing.T) {
	for _, enabled := range []bool{false, true} {
		rendered := renderAgentChart(t, "--set", fmt.Sprintf("rbac.discovery.readFlux=%t", enabled))
		marker := "- name: ENVPLANE_DISCOVERY_READ_FLUX"
		_, env, ok := strings.Cut(rendered, marker)
		if !ok || !strings.HasPrefix(strings.TrimSpace(env), fmt.Sprintf("value: %q", fmt.Sprint(enabled))) {
			t.Fatalf("Flux discovery runtime does not match RBAC enabled=%v", enabled)
		}
	}
}
