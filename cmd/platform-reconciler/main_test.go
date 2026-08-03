package main

import (
	"strings"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic/fake"
	kfake "k8s.io/client-go/kubernetes/fake"
)

func TestDetectCompatibleExistingCapabilities(t *testing.T) {
	objects := []runtime.Object{
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "networking.k8s.io/v1", "kind": "IngressClass", "metadata": map[string]any{"name": "nginx"}, "spec": map[string]any{"controller": "k8s.io/ingress-nginx"}}},
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "storage.k8s.io/v1", "kind": "StorageClass", "metadata": map[string]any{"name": "standard", "annotations": map[string]any{"storageclass.kubernetes.io/is-default-class": "true"}}, "provisioner": "rancher.io/local-path"}},
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "v1", "kind": "Service", "metadata": map[string]any{"name": "ingress-nginx-controller", "namespace": "ingress-nginx", "labels": map[string]any{"app.kubernetes.io/component": "controller"}}}},
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "v1", "kind": "Endpoints", "metadata": map[string]any{"name": "ingress-nginx-controller", "namespace": "ingress-nginx"}, "subsets": []any{map[string]any{"addresses": []any{map[string]any{"ip": "10.0.0.1"}}}}}},
	}
	client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), map[schema.GroupVersionResource]string{
		{Group: "networking.k8s.io", Version: "v1", Resource: "ingressclasses"}: "IngressClassList",
		{Version: "v1", Resource: "services"}:                                   "ServiceList",
		{Version: "v1", Resource: "endpoints"}:                                  "EndpointsList",
		{Group: "storage.k8s.io", Version: "v1", Resource: "storageclasses"}:    "StorageClassList",
	}, objects...)
	if ok, ref, err := detect("ingress", capability{Provider: "nginx", ExistingClassName: "nginx"}, client); err != nil || !ok || ref != "nginx" {
		t.Fatalf("ingress detection = %v %q %v", ok, ref, err)
	}
	if ok, ref, err := detect("storage", capability{}, client); err != nil || !ok || ref != "standard" {
		t.Fatalf("storage detection = %v %q %v", ok, ref, err)
	}
}

func TestManagedCapabilityWithoutPinnedChartIsActionable(t *testing.T) {
	client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), map[schema.GroupVersionResource]string{})
	result, err := reconcile("ingress", capability{Mode: "managed", Provider: "nginx"}, client, nil)
	if err == nil || result.State != "incompatible" {
		t.Fatalf("managed validation = %#v, %v", result, err)
	}
}

func TestOrphanIngressClassIsDegradedNotReady(t *testing.T) {
	client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), map[schema.GroupVersionResource]string{{Version: "v1", Resource: "services"}: "ServiceList", {Version: "v1", Resource: "endpoints"}: "EndpointsList", {Group: "networking.k8s.io", Version: "v1", Resource: "ingressclasses"}: "IngressClassList"}, &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "networking.k8s.io/v1", "kind": "IngressClass",
		"metadata": map[string]any{"name": "nginx"},
		"spec":     map[string]any{"controller": "k8s.io/ingress-nginx"},
	}})
	ok, _, err := detect("ingress", capability{Provider: "nginx", ExistingClassName: "nginx"}, client)
	if err != nil || ok {
		t.Fatalf("orphan ingress class detected as ready: ok=%v err=%v", ok, err)
	}
}

func TestDetectCompatibleExternalDNS(t *testing.T) {
	objects := []runtime.Object{
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "v1", "kind": "Secret", "metadata": map[string]any{"name": "dns-credentials", "namespace": "envpilot"}, "data": map[string]any{"credentials": "redacted"}}},
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "apps/v1", "kind": "Deployment", "metadata": map[string]any{"name": "external-dns", "namespace": "envpilot", "labels": map[string]any{"app.kubernetes.io/name": "external-dns"}}, "spec": map[string]any{"template": map[string]any{"spec": map[string]any{"containers": []any{map[string]any{"name": "external-dns", "args": []any{"--domain-filter=example.test", "--txt-owner-id=envpilot", "--policy=sync"}}}}}}, "status": map[string]any{"availableReplicas": int64(1)}}},
	}
	client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), map[schema.GroupVersionResource]string{
		{Version: "v1", Resource: "secrets"}:                    "SecretList",
		{Group: "apps", Version: "v1", Resource: "deployments"}: "DeploymentList",
	}, objects...)
	dep := capability{Provider: "external-dns", Namespace: "envpilot", Credentials: credentialsConfig{ExistingSecret: "dns-credentials"}, DomainFilters: []string{"example.test"}, OwnershipID: "envpilot", Policy: "sync"}
	ok, ref, err := detect("dns", dep, client)
	if err != nil || !ok || ref != "envpilot/external-dns" {
		t.Fatalf("external-dns detection = %v %q %v", ok, ref, err)
	}
}

func TestExternalDNSScopeMismatchIsIncompatible(t *testing.T) {
	objects := []runtime.Object{
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "v1", "kind": "Secret", "metadata": map[string]any{"name": "dns-credentials", "namespace": "envpilot"}, "data": map[string]any{"credentials": "redacted"}}},
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "apps/v1", "kind": "Deployment", "metadata": map[string]any{"name": "external-dns", "namespace": "envpilot", "labels": map[string]any{"app.kubernetes.io/name": "external-dns"}}, "spec": map[string]any{"template": map[string]any{"spec": map[string]any{"containers": []any{map[string]any{"name": "external-dns", "args": []any{"--domain-filter=other.test", "--txt-owner-id=envpilot", "--policy=sync"}}}}}}, "status": map[string]any{"availableReplicas": int64(1)}}},
	}
	client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), map[schema.GroupVersionResource]string{{Version: "v1", Resource: "secrets"}: "SecretList", {Group: "apps", Version: "v1", Resource: "deployments"}: "DeploymentList"}, objects...)
	dep := capability{Provider: "external-dns", Namespace: "envpilot", Credentials: credentialsConfig{ExistingSecret: "dns-credentials"}, DomainFilters: []string{"example.test"}, OwnershipID: "envpilot", Policy: "sync"}
	if _, _, err := detect("dns", dep, client); err == nil || !strings.Contains(err.Error(), "incompatible") {
		t.Fatalf("expected scope mismatch, got %v", err)
	}
}

func TestCleanupSkipsExternallyOwnedProvider(t *testing.T) {
	err := cleanup(config{Ingress: capability{Mode: "managed", Ownership: "external", Managed: managedConfig{CleanupPolicy: "delete", ReleaseName: "external"}}}, nil)
	if err != nil {
		t.Fatalf("cleanup touched an externally owned provider: %v", err)
	}
}

func TestEnsureNamespacesIsIdempotent(t *testing.T) {
	client := kfake.NewSimpleClientset()
	if err := ensureNamespaces(client, "ingress-nginx, ingress-nginx"); err != nil {
		t.Fatalf("ensure provider namespace: %v", err)
	}
	if err := ensureNamespaces(client, "ingress-nginx"); err != nil {
		t.Fatalf("repeat ensure provider namespace: %v", err)
	}
	if _, err := client.CoreV1().Namespaces().Get(ctx, "ingress-nginx", metav1.GetOptions{}); err != nil {
		t.Fatalf("provider namespace missing: %v", err)
	}
}
