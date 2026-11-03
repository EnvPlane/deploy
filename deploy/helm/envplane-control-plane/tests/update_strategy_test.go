package tests

import (
	"strings"
	"testing"
)

func TestControlPlaneUpdatesNeverOverlapIdentityCustody(t *testing.T) {
	for _, persistence := range []string{"true", "false"} {
		t.Run(persistence, func(t *testing.T) {
			rendered := renderControlPlaneChart(t,
				"--show-only", "templates/deployment.yaml",
				"--set", "persistence.enabled="+persistence,
				"--set", "finops.postgres.existingSecret=evidence-database",
				"--set", "strategy.type=RollingUpdate")
			if !strings.Contains(rendered, "strategy:\n    type: Recreate") || strings.Contains(rendered, "rollingUpdate:") {
				t.Fatal("singleton API updates may overlap installation identity custody")
			}
			if !strings.Contains(rendered, "replicas: 1") || !strings.Contains(rendered, "name: ENVPLANE_FINOPS_POSTGRES_DSN") {
				t.Fatal("evidence-connection upgrade lost its singleton API contract")
			}
		})
	}
}
