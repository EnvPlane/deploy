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

func TestBundledLedgerBootstrapIsInternalAndSecretBacked(t *testing.T) {
	for _, tc := range []struct {
		args []string
		want bool
	}{
		{nil, true},
		{[]string{"--set", "postgres.mode=external", "--set", "postgres.external.existingSecret=external"}, false},
		{[]string{"--set", "postgres.mode=disabled"}, false},
		{[]string{"--set", "finops.postgres.existingSecret=operator-ledger"}, false},
		{[]string{"--set", "finops.postgres.bootstrapInternal=false"}, false},
	} {
		rendered := renderControlPlaneChart(t, tc.args...)
		if strings.Contains(rendered, "name: ENVPLANE_FINOPS_BOOTSTRAP_PASSWORD") != tc.want {
			t.Fatal("unexpected bootstrap mode")
		}
		if tc.want && (!strings.Contains(rendered, "helm.sh/resource-policy: keep") || !strings.Contains(rendered, "key: password")) {
			t.Fatal("ledger credential not retained/Secret-backed")
		}
	}
}
