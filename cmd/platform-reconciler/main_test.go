package main

import (
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/dynamic/fake"
)

func TestDetectCompatibleExistingCapabilities(t *testing.T) {
	objects := []runtime.Object{
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "networking.k8s.io/v1", "kind": "IngressClass", "metadata": map[string]any{"name": "nginx"}, "spec": map[string]any{"controller": "k8s.io/ingress-nginx"}}},
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "storage.k8s.io/v1", "kind": "StorageClass", "metadata": map[string]any{"name": "standard", "annotations": map[string]any{"storageclass.kubernetes.io/is-default-class": "true"}}}},
	}
	client := fake.NewSimpleDynamicClient(runtime.NewScheme(), objects...)
	if ok, ref, err := detect("ingress", capability{ExistingClassName: "nginx"}, client); err != nil || !ok || ref != "nginx" {
		t.Fatalf("ingress detection = %v %q %v", ok, ref, err)
	}
	if ok, ref, err := detect("storage", capability{}, client); err != nil || !ok || ref != "standard" {
		t.Fatalf("storage detection = %v %q %v", ok, ref, err)
	}
}

func TestManagedCapabilityWithoutPinnedChartIsActionable(t *testing.T) {
	client := fake.NewSimpleDynamicClient(runtime.NewScheme())
	result, err := reconcile("ingress", capability{Mode: "managed", Provider: "nginx"}, client, nil)
	if err == nil || result.State != "incompatible" {
		t.Fatalf("managed validation = %#v, %v", result, err)
	}
}

func TestCleanupSkipsExternallyOwnedProvider(t *testing.T) {
	err := cleanup(config{Ingress: capability{Mode: "managed", Ownership: "external", Managed: managedConfig{CleanupPolicy: "delete", ReleaseName: "external"}}}, nil)
	if err != nil {
		t.Fatalf("cleanup touched an externally owned provider: %v", err)
	}
}
