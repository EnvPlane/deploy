package tests

import (
	"io"
	"reflect"
	"strings"
	"testing"

	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/util/yaml"
)

func TestSameClusterInstallerCanDelegateReadOnlyPodMetrics(t *testing.T) {
	rendered := renderControlPlaneChart(t, "--set", "rbac.sameClusterProjectExecutors.enabled=true",
		"--set", "rbac.sameClusterProjectExecutors.namespace=project-runtime")
	decoder := yaml.NewYAMLOrJSONDecoder(strings.NewReader(rendered), 4096)
	seen := map[string]bool{}
	for {
		var object rbacv1.Role
		if err := decoder.Decode(&object); err != nil {
			if err == io.EOF {
				break
			}
			t.Fatalf("decode chart: %v", err)
		}
		for _, rule := range object.Rules {
			for _, group := range rule.APIGroups {
				if group != "metrics.k8s.io" {
					continue
				}
				if !reflect.DeepEqual(rule.Resources, []string{"pods"}) ||
					!reflect.DeepEqual(rule.Verbs, []string{"get", "list"}) {
					t.Fatalf("unexpected metrics privileges: %+v", rule)
				}
				switch {
				case strings.HasSuffix(object.Name, "-same-cluster-project-executors"):
					if object.Kind != "Role" || object.Namespace != "project-runtime" {
						t.Fatal("executor metrics must be namespace scoped")
					}
					seen["executor"] = true
				case strings.HasSuffix(object.Name, "-same-cluster-project-executor-release-manager"):
					if object.Kind != "ClusterRole" {
						t.Fatal("release manager must hold delegated discovery contract")
					}
					seen["installer"] = true
				default:
					t.Fatalf("unexpected metrics reader: %s/%s", object.Kind, object.Name)
				}
			}
		}
	}
	if !reflect.DeepEqual(seen, map[string]bool{"executor": true, "installer": true}) {
		t.Fatalf("missing installer metrics contract: %v", seen)
	}
}
