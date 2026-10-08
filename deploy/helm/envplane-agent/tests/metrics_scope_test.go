package tests

import (
	"io"
	"reflect"
	"strings"
	"testing"

	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/util/yaml"
)

func TestAgentMetricsDiscoveryIsReadOnlyAndNamespaceScoped(t *testing.T) {
	rendered := renderAgentChart(t, "--set", "rbac.discovery.scope=namespace",
		"--set", "rbac.discovery.namespaces={tenant-alpha,tenant-beta}",
		"--set", "rbac.discovery.clusterCapabilityRead=true",
		"--set", "rbac.discovery.readSecrets=false")
	decoder := yaml.NewYAMLOrJSONDecoder(strings.NewReader(rendered), 4096)
	seen := map[string]bool{}
	bindings := map[string]bool{}
	for {
		var object struct {
			Kind     string `json:"kind"`
			Metadata struct {
				Name      string `json:"name"`
				Namespace string `json:"namespace"`
			} `json:"metadata"`
			Rules   []rbacv1.PolicyRule `json:"rules"`
			RoleRef rbacv1.RoleRef      `json:"roleRef"`
		}
		if err := decoder.Decode(&object); err != nil {
			if err == io.EOF {
				break
			}
			t.Fatalf("decode chart: %v", err)
		}
		if object.Kind == "RoleBinding" && strings.HasSuffix(object.RoleRef.Name, "-discovery-reader") {
			if object.RoleRef.Kind != "Role" {
				t.Fatal("metrics discovery must bind a namespaced Role")
			}
			bindings[object.Metadata.Namespace] = true
		}
		for _, rule := range object.Rules {
			for _, group := range rule.APIGroups {
				if group != "metrics.k8s.io" {
					continue
				}
				if object.Kind != "Role" || !reflect.DeepEqual(rule.Resources, []string{"pods"}) ||
					!reflect.DeepEqual(rule.Verbs, []string{"get", "list"}) {
					t.Fatalf("unexpected metrics privileges: %+v", object)
				}
				seen[object.Metadata.Namespace] = true
			}
		}
	}
	want := map[string]bool{"tenant-alpha": true, "tenant-beta": true}
	if !reflect.DeepEqual(seen, want) || !reflect.DeepEqual(bindings, want) {
		t.Fatalf("metrics namespaces=%v bindings=%v want=%v", seen, bindings, want)
	}
}
