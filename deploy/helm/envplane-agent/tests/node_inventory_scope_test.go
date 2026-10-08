package tests

import (
	"fmt"
	"io"
	"os/exec"
	"reflect"
	"strings"
	"testing"

	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/util/yaml"
)

func TestNodeInventoryIsExplicitReadOnlyOptIn(t *testing.T) {
	for _, scope := range []string{"namespace", "cluster"} {
		for _, enabled := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s-%t", scope, enabled), func(t *testing.T) {
				rendered := renderAgentChart(t, "--set", "rbac.discovery.scope="+scope,
					"--set", fmt.Sprintf("rbac.discovery.nodeInventoryEnabled=%t", enabled))
				marker := "- name: ENVPLANE_FINOPS_NODE_INVENTORY_ENABLED"
				_, env, ok := strings.Cut(rendered, marker)
				if !ok || !strings.HasPrefix(strings.TrimSpace(env), fmt.Sprintf("value: %q", fmt.Sprint(enabled))) {
					t.Fatal("runtime flag must match RBAC opt-in")
				}
				decoder := yaml.NewYAMLOrJSONDecoder(strings.NewReader(rendered), 4096)
				count := 0
				for {
					var object rbacv1.Role
					if err := decoder.Decode(&object); err != nil {
						if err == io.EOF {
							break
						}
						t.Fatal(err)
					}
					for _, rule := range object.Rules {
						for _, resource := range rule.Resources {
							if !strings.HasPrefix(resource, "nodes") {
								continue
							}
							if !enabled || object.Kind != "ClusterRole" ||
								!reflect.DeepEqual(rule.APIGroups, []string{""}) ||
								!reflect.DeepEqual(rule.Resources, []string{"nodes"}) ||
								!reflect.DeepEqual(rule.Verbs, []string{"get", "list"}) {
								t.Fatalf("unexpected node privileges: %+v", rule)
							}
							count++
						}
					}
				}
				want := 0
				if enabled {
					want = 1
				}
				if count != want {
					t.Fatalf("node rules=%d want=%d", count, want)
				}
			})
		}
	}
}

func TestNodeInventoryDefaultDisabledAndTyped(t *testing.T) {
	rendered := renderAgentChart(t)
	if strings.Contains(rendered, `resources: ["nodes"]`) || !strings.Contains(rendered, "ENVPLANE_FINOPS_NODE_INVENTORY_ENABLED\n              value: \"false\"") {
		t.Fatal("default must not read Node capacity")
	}
	output, err := exec.Command("helm", "template", "test", "..", "--set-string", "rbac.discovery.nodeInventoryEnabled=false").CombinedOutput()
	if err == nil || !strings.Contains(string(output), "nodeInventoryEnabled") {
		t.Fatal("string false must be rejected rather than truthy")
	}
}
