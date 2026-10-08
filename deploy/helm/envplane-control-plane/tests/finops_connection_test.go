package tests

import (
	"strings"
	"testing"
)

func TestMeteringDatabaseConnectionUsesSecretIndependentOfRedis(t *testing.T) {
	for _, mode := range []string{"internal", "disabled"} {
		rendered := renderControlPlaneChart(t, "--set", "finops.postgres.existingSecret=metering-database", "--set", "finops.postgres.dsnKey=connection", "--set", "redis.mode="+mode)
		for _, expected := range []string{"name: ENVPLANE_FINOPS_POSTGRES_DSN", "name: \"metering-database\"", "key: \"connection\""} {
			if !strings.Contains(rendered, expected) {
				t.Fatalf("redis %s missing Secret-backed metering connection: %s", mode, expected)
			}
		}
	}
}
