package tests

import (
	"errors"
	"io"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/yaml"
)

type renderedAccessObject struct {
	Kind     string              `json:"kind"`
	Metadata metav1.ObjectMeta   `json:"metadata"`
	Rules    []rbacv1.PolicyRule `json:"rules"`
	RoleRef  rbacv1.RoleRef      `json:"roleRef"`
	Subjects []rbacv1.Subject    `json:"subjects"`
}

func renderRemoteAccessProfile(t *testing.T, args ...string) []renderedAccessObject {
	t.Helper()
	script := filepath.Join("..", "..", "..", "..", "scripts", "render-remote-cluster-rbac-profile.sh")
	output, err := exec.Command("bash", append([]string{script, "--cluster-id", "arbitrary-target"}, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("render access profile: %v: %s", err, output)
	}
	decoder := yaml.NewYAMLOrJSONDecoder(strings.NewReader(string(output)), 4096)
	var objects []renderedAccessObject
	for {
		var object renderedAccessObject
		if err := decoder.Decode(&object); errors.Is(err, io.EOF) {
			break
		} else if err != nil {
			t.Fatalf("decode access profile: %v", err)
		}
		if object.Kind != "" {
			objects = append(objects, object)
		}
	}
	return objects
}

func TestRemoteFluxStatusProfileIsOptInAndGetOnly(t *testing.T) {
	const parentName = "envplane-remote-cluster-arbitrary-target-flux-status-parent"
	for _, object := range renderRemoteAccessProfile(t, "--project-id", "arbitrary-project") {
		if object.Metadata.Name == parentName {
			t.Fatal("default profile must not grant future-name Flux access")
		}
	}
	for _, namespace := range []string{"flux-system", "gitops-engine"} {
		t.Run(namespace, func(t *testing.T) {
			objects := renderRemoteAccessProfile(t, "--flux-status-reader-namespace", namespace, "--flux-status-reader-namespace", namespace)
			roles, bindings := 0, 0
			for _, object := range objects {
				if object.Metadata.Name != parentName {
					continue
				}
				if object.Metadata.Namespace != namespace {
					t.Fatalf("profile leaked to namespace %q", object.Metadata.Namespace)
				}
				switch object.Kind {
				case "Role":
					roles++
					want := []rbacv1.PolicyRule{{APIGroups: []string{"kustomize.toolkit.fluxcd.io"}, Resources: []string{"kustomizations"}, Verbs: []string{"get"}}}
					if !reflect.DeepEqual(object.Rules, want) {
						t.Fatalf("status parent must contain only namespace-wide get, no Secret/list/watch/write access: %+v", object.Rules)
					}
					if object.Metadata.Annotations["envplane.io/access-profile"] != "dynamic-flux-status-get-v1" {
						t.Fatal("missing reviewed access profile identity")
					}
				case "RoleBinding":
					bindings++
					wantRef := rbacv1.RoleRef{APIGroup: "rbac.authorization.k8s.io", Kind: "Role", Name: parentName}
					wantSubjects := []rbacv1.Subject{{Kind: "ServiceAccount", Name: "envplane-remote-cluster-arbitrary-target", Namespace: "envplane-system"}}
					if !reflect.DeepEqual(object.RoleRef, wantRef) || !reflect.DeepEqual(object.Subjects, wantSubjects) {
						t.Fatalf("unexpected status parent binding: %+v", object)
					}
				default:
					t.Fatalf("unexpected status parent object kind %q", object.Kind)
				}
			}
			if roles != 1 || bindings != 1 {
				t.Fatalf("repeated opt-in must render one Role/RoleBinding, got %d/%d", roles, bindings)
			}
		})
	}
}
