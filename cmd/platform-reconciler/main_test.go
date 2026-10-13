package main

import (
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/dynamic/fake"
	kfake "k8s.io/client-go/kubernetes/fake"
	"k8s.io/client-go/tools/clientcmd"
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
		{Group: "discovery.k8s.io", Version: "v1", Resource: "endpointslices"}:  "EndpointSliceList",
		{Group: "storage.k8s.io", Version: "v1", Resource: "storageclasses"}:    "StorageClassList",
	}, objects...)
	if ok, ref, err := detect("ingress", capability{Provider: "nginx", ExistingClassName: "nginx"}, client); err != nil || !ok || ref != "nginx" {
		t.Fatalf("ingress detection = %v %q %v", ok, ref, err)
	}
	if ok, ref, err := detect("storage", capability{}, client); err != nil || !ok || ref != "standard" {
		t.Fatalf("storage detection = %v %q %v", ok, ref, err)
	}
}

func TestPersistStatusWritesGenerationAwareSnapshot(t *testing.T) {
	t.Setenv("ENVPLANE_RECONCILE_NAMESPACE", "envplane")
	t.Setenv("ENVPLANE_RECONCILE_STATUS_CONFIG_MAP", "envplane-platform-dependency-reconciler-status")
	client := kfake.NewSimpleClientset()
	statuses := map[string]result{
		"ingress": {Mode: "auto", Provider: "nginx", Ownership: "external", State: "detected", UpdatedAt: "2026-08-03T00:00:00Z"},
		"dns":     {Mode: "disabled", Ownership: "external", State: "disabled"},
		"storage": {Mode: "disabled", Ownership: "external", State: "disabled"},
	}
	if err := persistStatus(client, statuses); err != nil {
		t.Fatalf("persist first status: %v", err)
	}
	if err := persistStatus(client, statuses); err != nil {
		t.Fatalf("persist second status: %v", err)
	}
	cm, err := client.CoreV1().ConfigMaps("envplane").Get(ctx, "envplane-platform-dependency-reconciler-status", metav1.GetOptions{})
	if err != nil {
		t.Fatalf("get status ConfigMap: %v", err)
	}
	var snapshot statusSnapshot
	if err := json.Unmarshal([]byte(cm.Data["status.json"]), &snapshot); err != nil {
		t.Fatalf("decode snapshot: %v", err)
	}
	if snapshot.SchemaVersion != statusSnapshotSchemaVersion || snapshot.Generation != 2 || snapshot.ObservedAt == "" || snapshot.Dependencies["ingress"].State != "detected" {
		t.Fatalf("snapshot = %#v", snapshot)
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
	if !errors.Is(err, errIngressClassUnhealthy) || ok {
		t.Fatalf("orphan ingress class detected as ready: ok=%v err=%v", ok, err)
	}
	r, err := reconcile("ingress", capability{Mode: "auto", Provider: "nginx", ExistingClassName: "nginx"}, client, nil)
	if r.State != "degraded" || !errors.Is(err, errIngressClassUnhealthy) {
		t.Fatalf("auto mode adopted orphan class: %#v, %v", r, err)
	}
}

func TestDetectExistingTraefikRequiresMatchingReadyController(t *testing.T) {
	class := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "networking.k8s.io/v1", "kind": "IngressClass",
		"metadata": map[string]any{"name": "traefik"},
		"spec":     map[string]any{"controller": "traefik.io/ingress-controller"},
	}}
	service := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "Service",
		"metadata": map[string]any{"name": "traefik", "namespace": "traefik", "labels": map[string]any{"app.kubernetes.io/name": "traefik", "app.kubernetes.io/instance": "traefik-traefik"}},
		"spec":     map[string]any{"selector": map[string]any{"app.kubernetes.io/name": "traefik", "app.kubernetes.io/instance": "traefik-traefik"}},
	}}
	deployment := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "apps/v1", "kind": "Deployment",
		"metadata": map[string]any{"name": "traefik", "namespace": "traefik", "labels": map[string]any{"app.kubernetes.io/name": "traefik", "app.kubernetes.io/instance": "traefik-traefik"}},
		"spec":     map[string]any{"selector": map[string]any{"matchLabels": map[string]any{"app.kubernetes.io/name": "traefik", "app.kubernetes.io/instance": "traefik-traefik"}}},
		"status":   map[string]any{"availableReplicas": int64(1)},
	}}
	slice := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "discovery.k8s.io/v1", "kind": "EndpointSlice",
		"metadata":  map[string]any{"name": "traefik-1", "namespace": "traefik", "labels": map[string]any{"kubernetes.io/service-name": "traefik"}},
		"endpoints": []any{map[string]any{"addresses": []any{"10.0.0.1"}, "conditions": map[string]any{"ready": true}}},
	}}
	kinds := map[schema.GroupVersionResource]string{
		{Group: "networking.k8s.io", Version: "v1", Resource: "ingressclasses"}: "IngressClassList",
		{Version: "v1", Resource: "services"}:                                   "ServiceList",
		{Version: "v1", Resource: "endpoints"}:                                  "EndpointsList",
		{Group: "discovery.k8s.io", Version: "v1", Resource: "endpointslices"}:  "EndpointSliceList",
		{Group: "apps", Version: "v1", Resource: "deployments"}:                 "DeploymentList",
	}
	dep := capability{Mode: "existing", Provider: "traefik", ExistingClassName: "traefik", Namespace: "traefik"}
	for _, tc := range []struct {
		name     string
		edit     func(*unstructured.Unstructured, *unstructured.Unstructured, *unstructured.Unstructured, *unstructured.Unstructured)
		want     bool
		mismatch bool
	}{
		{name: "healthy", want: true},
		{name: "wrong controller", mismatch: true, edit: func(c, _, _, _ *unstructured.Unstructured) {
			c.Object["spec"] = map[string]any{"controller": "k8s.io/ingress-nginx"}
		}},
		{name: "wrong service identity", edit: func(_, s, _, _ *unstructured.Unstructured) {
			s.SetLabels(map[string]string{"app.kubernetes.io/name": "unrelated", "app.kubernetes.io/instance": "traefik-traefik"})
		}},
		{name: "wrong service selector", edit: func(_, s, _, _ *unstructured.Unstructured) {
			s.Object["spec"] = map[string]any{"selector": map[string]any{"app.kubernetes.io/name": "other", "app.kubernetes.io/instance": "traefik-traefik"}}
		}},
		{name: "wrong deployment selector", edit: func(_, _, d, _ *unstructured.Unstructured) {
			d.Object["spec"] = map[string]any{"selector": map[string]any{"matchLabels": map[string]any{"app.kubernetes.io/name": "other", "app.kubernetes.io/instance": "traefik-traefik"}}}
		}},
		{name: "wrong namespace", edit: func(_, s, _, _ *unstructured.Unstructured) { s.SetNamespace("other") }},
		{name: "unready deployment", edit: func(_, _, d, _ *unstructured.Unstructured) {
			d.Object["status"] = map[string]any{"availableReplicas": int64(0)}
		}},
		{name: "unready endpoint", edit: func(_, _, _, e *unstructured.Unstructured) {
			e.Object["endpoints"] = []any{map[string]any{"addresses": []any{"10.0.0.1"}, "conditions": map[string]any{"ready": false}}}
		}},
		{name: "unrelated endpoint slice", edit: func(_, _, _, e *unstructured.Unstructured) {
			e.SetLabels(map[string]string{"kubernetes.io/service-name": "other"})
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, s, d, e := class.DeepCopy(), service.DeepCopy(), deployment.DeepCopy(), slice.DeepCopy()
			if tc.edit != nil {
				tc.edit(c, s, d, e)
			}
			client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), kinds, c, s, d, e)
			result, err := reconcile("ingress", dep, client, nil)
			if tc.mismatch {
				if result.State != "incompatible" || err == nil {
					t.Fatalf("mismatch = %#v, %v", result, err)
				}
				return
			}
			if tc.want {
				if result.State != "detected" || result.Reference != "traefik" || err != nil {
					t.Fatalf("healthy = %#v, %v", result, err)
				}
			} else if result.State != "degraded" || !errors.Is(err, errIngressClassUnhealthy) {
				t.Fatalf("unhealthy = %#v, %v", result, err)
			}
		})
	}
}

func TestManagedIngressProviderPinsAreIndependent(t *testing.T) {
	for _, name := range []string{"nginx", "ingress-nginx", "traefik"} {
		provider := ingressProviders[name]
		dep := capability{Provider: name, Namespace: "traefik", ExistingClassName: "traefik", Managed: managedConfig{Namespace: "traefik", ChartRef: provider.Chart, Version: provider.ChartVersion, ChartSHA256: "sha256:" + provider.ChartSHA256, RBACRules: []map[string]any{{"apiGroups": []string{""}, "resources": []string{"secrets"}, "verbs": []string{"get"}}}}}
		if err := validateManagedIngress(dep); err != nil {
			t.Fatalf("%s pin rejected: %v", name, err)
		}
		for _, change := range []struct {
			name string
			edit func(*managedConfig)
		}{
			{name: "wrong chart", edit: func(m *managedConfig) { m.ChartRef = "oci://ghcr.io/unrelated/chart" }},
			{name: "wrong version", edit: func(m *managedConfig) { m.Version = "0.0.0" }},
			{name: "wrong digest", edit: func(m *managedConfig) { m.ChartSHA256 = strings.Repeat("0", 64) }},
		} {
			t.Run(name+"/"+change.name, func(t *testing.T) {
				bad := dep
				change.edit(&bad.Managed)
				if err := validateManagedIngress(bad); err == nil {
					t.Fatal("invalid managed chart accepted")
				}
			})
		}
		if name == "traefik" {
			bad := dep
			bad.Managed.RBACRules = nil
			if err := validateManagedIngress(bad); err == nil || !strings.Contains(err.Error(), "rbacRules") {
				t.Fatalf("Traefik without installer permissions = %v", err)
			}
		}
	}
}

func TestLiveTraefikDetection(t *testing.T) {
	path := os.Getenv("ENVPLANE_RECONCILER_TEST_KUBECONFIG")
	if path == "" {
		t.Skip("set ENVPLANE_RECONCILER_TEST_KUBECONFIG for a read-only live check")
	}
	config, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(
		&clientcmd.ClientConfigLoadingRules{ExplicitPath: path},
		&clientcmd.ConfigOverrides{CurrentContext: "envplane"},
	).ClientConfig()
	if err != nil {
		t.Fatal(err)
	}
	client, err := dynamic.NewForConfig(config)
	if err != nil {
		t.Fatal(err)
	}
	r, err := reconcile("ingress", capability{Mode: "existing", Provider: "traefik", Namespace: "traefik", ExistingClassName: "traefik"}, client, nil)
	if err != nil || r.State != "detected" || r.Reference != "traefik" {
		t.Fatalf("live Traefik = %#v, %v", r, err)
	}
}

func TestIngressSmokeHostDoesNotReuseAccessRoute(t *testing.T) {
	for input, want := range map[string]string{
		"envplane.local":    "envplane-smoke.envplane.local",
		"*.example.test":    "envplane-smoke.example.test",
		"  preview.example": "envplane-smoke.preview.example",
	} {
		if got := ingressSmokeHost(input); got != want {
			t.Fatalf("ingressSmokeHost(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestDetectCompatibleExternalDNS(t *testing.T) {
	objects := []runtime.Object{
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "v1", "kind": "Secret", "metadata": map[string]any{"name": "dns-credentials", "namespace": "envplane"}, "data": map[string]any{"credentials": "redacted"}}},
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "apps/v1", "kind": "Deployment", "metadata": map[string]any{"name": "external-dns", "namespace": "envplane", "labels": map[string]any{"app.kubernetes.io/name": "external-dns"}}, "spec": map[string]any{"template": map[string]any{"spec": map[string]any{"containers": []any{map[string]any{"name": "external-dns", "args": []any{"--domain-filter=example.test", "--txt-owner-id=envplane", "--policy=sync"}}}}}}, "status": map[string]any{"availableReplicas": int64(1)}}},
	}
	client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), map[schema.GroupVersionResource]string{
		{Version: "v1", Resource: "secrets"}:                    "SecretList",
		{Group: "apps", Version: "v1", Resource: "deployments"}: "DeploymentList",
	}, objects...)
	dep := capability{Provider: "external-dns", Namespace: "envplane", Credentials: credentialsConfig{ExistingSecret: "dns-credentials"}, DomainFilters: []string{"example.test"}, OwnershipID: "envplane", Policy: "sync"}
	ok, ref, err := detect("dns", dep, client)
	if err != nil || !ok || ref != "envplane/external-dns" {
		t.Fatalf("external-dns detection = %v %q %v", ok, ref, err)
	}
}

func TestExternalDNSScopeMismatchIsIncompatible(t *testing.T) {
	objects := []runtime.Object{
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "v1", "kind": "Secret", "metadata": map[string]any{"name": "dns-credentials", "namespace": "envplane"}, "data": map[string]any{"credentials": "redacted"}}},
		&unstructured.Unstructured{Object: map[string]any{"apiVersion": "apps/v1", "kind": "Deployment", "metadata": map[string]any{"name": "external-dns", "namespace": "envplane", "labels": map[string]any{"app.kubernetes.io/name": "external-dns"}}, "spec": map[string]any{"template": map[string]any{"spec": map[string]any{"containers": []any{map[string]any{"name": "external-dns", "args": []any{"--domain-filter=other.test", "--txt-owner-id=envplane", "--policy=sync"}}}}}}, "status": map[string]any{"availableReplicas": int64(1)}}},
	}
	client := fake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), map[schema.GroupVersionResource]string{{Version: "v1", Resource: "secrets"}: "SecretList", {Group: "apps", Version: "v1", Resource: "deployments"}: "DeploymentList"}, objects...)
	dep := capability{Provider: "external-dns", Namespace: "envplane", Credentials: credentialsConfig{ExistingSecret: "dns-credentials"}, DomainFilters: []string{"example.test"}, OwnershipID: "envplane", Policy: "sync"}
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

func TestEnsureNamespacesActionDoesNotRequireDependencyConfig(t *testing.T) {
	cfg, err := configForAction(actionEnsureNamespaces, "{")
	if err != nil {
		t.Fatalf("namespace action must not decode dependency config: %v", err)
	}
	if cfg.Ingress.Mode != "" || cfg.DNS.Mode != "" || cfg.Storage.Mode != "" {
		t.Fatalf("namespace action returned unexpected config: %#v", cfg)
	}
}

func TestReconcileActionRequiresNonEmptyDependencyConfig(t *testing.T) {
	_, err := configForAction("reconcile", " \t\n")
	if err == nil || !strings.Contains(err.Error(), "reconciliation config is required") {
		t.Fatalf("expected actionable missing-config error, got %v", err)
	}
}

func TestReconcileFluxHealthCheckRecoveryEnablesOnlyExpectedGate(t *testing.T) {
	t.Setenv("ENVPLANE_FLUX_RECOVERY_ENABLED", "true")
	t.Setenv("ENVPLANE_FLUX_RECOVERY_NAMESPACE", "flux-system")
	t.Setenv("ENVPLANE_FLUX_RECOVERY_DEPLOYMENT", "kustomize-controller")
	client := kfake.NewSimpleClientset(&appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: "kustomize-controller", Namespace: "flux-system"},
		Spec: appsv1.DeploymentSpec{
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Name: "manager",
						Args: []string{"--log-level=info", "--feature-gates=OtherFeature=true,CancelHealthCheckOnNewRevision=false"},
					}},
				},
			},
		},
	})

	result, err := reconcileFluxHealthCheckRecovery(client)
	if err != nil || result.State != "configured" || result.Reference != "flux-system/kustomize-controller" {
		t.Fatalf("unexpected recovery result: %#v, %v", result, err)
	}
	updated, err := client.AppsV1().Deployments("flux-system").Get(ctx, "kustomize-controller", metav1.GetOptions{})
	if err != nil {
		t.Fatal(err)
	}
	args := strings.Join(updated.Spec.Template.Spec.Containers[0].Args, " ")
	if !strings.Contains(args, "OtherFeature=true") || !strings.Contains(args, "CancelHealthCheckOnNewRevision=true") {
		t.Fatalf("feature gates were not preserved and enabled: %q", args)
	}
}

func TestReconcileFluxHealthCheckRecoverySkipsAbsentFlux(t *testing.T) {
	t.Setenv("ENVPLANE_FLUX_RECOVERY_ENABLED", "true")
	t.Setenv("ENVPLANE_FLUX_RECOVERY_NAMESPACE", "flux-system")
	t.Setenv("ENVPLANE_FLUX_RECOVERY_DEPLOYMENT", "kustomize-controller")
	result, err := reconcileFluxHealthCheckRecovery(kfake.NewSimpleClientset())
	if err != nil || result.State != "absent" {
		t.Fatalf("unexpected absent Flux result: %#v, %v", result, err)
	}
}
