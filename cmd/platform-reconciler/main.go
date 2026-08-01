// platform-reconciler is deliberately limited to external platform
// capabilities. It never installs EnvPilot core charts or workloads.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/cli"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/discovery/cached/memory"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/restmapper"
	"k8s.io/client-go/tools/clientcmd"
	clientcmdapi "k8s.io/client-go/tools/clientcmd/api"
)

type capability struct {
	Mode              string        `json:"mode"`
	Provider          string        `json:"provider"`
	ExistingClassName string        `json:"existingClassName"`
	ExistingSecret    string        `json:"existingSecret"`
	Namespace         string        `json:"namespace"`
	Version           string        `json:"version"`
	Ownership         string        `json:"ownership"`
	Managed           managedConfig `json:"managed"`
}
type managedConfig struct {
	ChartRef      string         `json:"chartRef"`
	Version       string         `json:"version"`
	ReleaseName   string         `json:"releaseName"`
	Namespace     string         `json:"namespace"`
	Values        map[string]any `json:"values"`
	CleanupPolicy string         `json:"cleanupPolicy"`
	Smoke         smokeConfig    `json:"smoke"`
}
type smokeConfig struct {
	ServiceName string `json:"serviceName"`
	Namespace   string `json:"namespace"`
	Port        int64  `json:"port"`
	Host        string `json:"host"`
}
type config struct {
	Ingress capability `json:"ingress"`
	DNS     capability `json:"dns"`
	Storage capability `json:"storage"`
}
type result struct {
	State     string `json:"state"`
	Mode      string `json:"mode"`
	Provider  string `json:"provider,omitempty"`
	Ownership string `json:"ownership,omitempty"`
	Reference string `json:"reference,omitempty"`
	Version   string `json:"version,omitempty"`
	Message   string `json:"message,omitempty"`
	UpdatedAt string `json:"updatedAt"`
}

var (
	ctx        = context.Background()
	statusData = map[string]result{}
)

type ingressProvider struct {
	Controller string
	Chart      string
}

var ingressProviders = map[string]ingressProvider{
	"nginx":         {Controller: "k8s.io/ingress-nginx", Chart: "oci://ghcr.io/ingress-nginx/ingress-nginx"},
	"ingress-nginx": {Controller: "k8s.io/ingress-nginx", Chart: "oci://ghcr.io/ingress-nginx/ingress-nginx"},
}

func main() {
	log.SetFlags(0)
	if err := run(); err != nil {
		log.Fatal(err)
	}
}
func run() error {
	var cfg config
	if err := json.Unmarshal([]byte(os.Getenv("ENVPILOT_RECONCILE_CONFIG_JSON")), &cfg); err != nil {
		// The chart normally supplies the ConfigMap through the API; accepting an
		// env value also makes the binary straightforward to exercise in tests.
		return fmt.Errorf("decode dependency config: %w", err)
	}
	restCfg, err := rest.InClusterConfig()
	if err != nil {
		return fmt.Errorf("in-cluster config: %w", err)
	}
	client, err := dynamic.NewForConfig(restCfg)
	if err != nil {
		return err
	}
	core, err := kubernetes.NewForConfig(restCfg)
	if err != nil {
		return err
	}
	if os.Getenv("ENVPILOT_RECONCILE_ACTION") == "cleanup" {
		return cleanup(cfg, restCfg)
	}
	for name, dep := range map[string]capability{"ingress": cfg.Ingress, "dns": cfg.DNS, "storage": cfg.Storage} {
		res, e := reconcile(name, dep, client, restCfg)
		if e != nil {
			if res.State == "" {
				res.State = "degraded"
			}
			res.Message = e.Error()
		}
		statusData[name] = res
	}
	return persistStatus(core, statusData)
}

func reconcile(name string, dep capability, client dynamic.Interface, restCfg *rest.Config) (result, error) {
	r := result{Mode: dep.Mode, Provider: dep.Provider, Ownership: dep.Ownership, Version: dep.Version, UpdatedAt: time.Now().UTC().Format(time.RFC3339)}
	if r.Ownership == "" {
		r.Ownership = "external"
	}
	if dep.Mode == "disabled" {
		r.State = "disabled"
		return r, nil
	}
	if dep.Mode == "existing" || dep.Mode == "auto" {
		found, reference, err := detect(name, dep, client)
		if err != nil {
			return r, err
		}
		if found {
			r.State = "detected"
			r.Reference = reference
			return r, nil
		}
		if dep.Mode == "existing" {
			r.State = "missing"
			return r, fmt.Errorf("configured existing %s capability is not healthy", name)
		}
	}
	if dep.Provider == "" || dep.Managed.ChartRef == "" || dep.Managed.Version == "" || dep.Managed.ReleaseName == "" {
		r.State = "incompatible"
		return r, fmt.Errorf("%s managed provider requires provider, managed.chartRef, managed.version and managed.releaseName", name)
	}
	if name == "ingress" {
		provider, ok := ingressProviders[dep.Provider]
		if !ok {
			r.State = "incompatible"
			return r, fmt.Errorf("unsupported ingress provider %q; configure a registered provider", dep.Provider)
		}
		if !strings.Contains(dep.Managed.ChartRef, "ingress-nginx") || dep.Managed.ChartRef != provider.Chart {
			r.State = "incompatible"
			return r, fmt.Errorf("ingress provider %s requires pinned chart %s", dep.Provider, provider.Chart)
		}
		if dep.ExistingClassName != "" {
			if item, err := client.Resource(schema.GroupVersionResource{Group: "networking.k8s.io", Version: "v1", Resource: "ingressclasses"}).Get(ctx, dep.ExistingClassName, metav1.GetOptions{}); err == nil {
				if spec, ok := item.Object["spec"].(map[string]any); !ok || spec["controller"] != provider.Controller {
					r.State = "incompatible"
					return r, fmt.Errorf("ingress class %s is owned by a different controller", dep.ExistingClassName)
				}
			}
		}
	}
	if err := helmApply(dep.Managed, restCfg); err != nil {
		return r, fmt.Errorf("managed %s provider: %w", name, err)
	}
	r.State = "managed"
	r.Ownership = "envpilot"
	if name == "ingress" && dep.Managed.Smoke.ServiceName != "" {
		if err := verifyIngressSmoke(dep, client); err != nil {
			r.State = "degraded"
			return r, err
		}
	}
	return r, nil
}

func detect(name string, dep capability, client dynamic.Interface) (bool, string, error) {
	switch name {
	case "ingress":
		provider, ok := ingressProviders[dep.Provider]
		if !ok {
			return false, "", fmt.Errorf("unsupported ingress provider %q; configure a registered provider", dep.Provider)
		}
		list, err := client.Resource(schema.GroupVersionResource{Group: "networking.k8s.io", Version: "v1", Resource: "ingressclasses"}).List(ctx, metav1.ListOptions{})
		if err != nil {
			return false, "", err
		}
		for _, item := range list.Items {
			if dep.ExistingClassName == "" || item.GetName() == dep.ExistingClassName {
				if c, ok := item.Object["spec"].(map[string]any); ok && c["controller"] == provider.Controller {
					if ingressControllerHealthy(client, item.GetName()) {
						return true, item.GetName(), nil
					}
				}
			}
		}
	case "storage":
		list, err := client.Resource(schema.GroupVersionResource{Group: "storage.k8s.io", Version: "v1", Resource: "storageclasses"}).List(ctx, metav1.ListOptions{})
		if err != nil {
			return false, "", err
		}
		for _, item := range list.Items {
			if dep.ExistingClassName != "" && item.GetName() == dep.ExistingClassName {
				return true, item.GetName(), nil
			}
			if dep.ExistingClassName == "" && item.GetAnnotations()["storageclass.kubernetes.io/is-default-class"] == "true" {
				return true, item.GetName(), nil
			}
		}
	case "dns":
		// DNS providers are represented by an operator-owned Secret reference;
		// no provider resource is adopted or mutated by this reconciler.
		if dep.ExistingSecret != "" {
			return true, dep.ExistingSecret, nil
		}
	}
	return false, "", nil
}

func ingressControllerHealthy(client dynamic.Interface, className string) bool {
	services, err := client.Resource(schema.GroupVersionResource{Version: "v1", Resource: "services"}).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}
	for _, service := range services.Items {
		labels := service.GetLabels()
		if !strings.Contains(service.GetName(), "ingress") && labels["app.kubernetes.io/component"] != "controller" {
			continue
		}
		endpoints, err := client.Resource(schema.GroupVersionResource{Version: "v1", Resource: "endpoints"}).Namespace(service.GetNamespace()).Get(ctx, service.GetName(), metav1.GetOptions{})
		if err != nil {
			continue
		}
		if subsets, ok := endpoints.Object["subsets"].([]any); ok && len(subsets) > 0 {
			for _, raw := range subsets {
				if s, ok := raw.(map[string]any); ok {
					if addresses, ok := s["addresses"].([]any); ok && len(addresses) > 0 {
						return true
					}
				}
			}
		}
		// EndpointSlice is the preferred discovery API on newer clusters.
		slices, err := client.Resource(schema.GroupVersionResource{Group: "discovery.k8s.io", Version: "v1", Resource: "endpointslices"}).Namespace(service.GetNamespace()).List(ctx, metav1.ListOptions{})
		if err == nil {
			for _, slice := range slices.Items {
				labels := slice.GetLabels()
				if labels["kubernetes.io/service-name"] != service.GetName() {
					continue
				}
				if endpoints, ok := slice.Object["endpoints"].([]any); ok {
					for _, raw := range endpoints {
						if endpoint, ok := raw.(map[string]any); ok {
							if conditions, ok := endpoint["conditions"].(map[string]any); ok && conditions["ready"] == false {
								continue
							}
							if addresses, ok := endpoint["addresses"].([]any); ok && len(addresses) > 0 {
								return true
							}
						}
					}
				}
			}
		}
	}
	_ = className
	return false
}

func verifyIngressSmoke(dep capability, client dynamic.Interface) error {
	smoke := dep.Managed.Smoke
	if smoke.Namespace == "" {
		smoke.Namespace = dep.Managed.Namespace
	}
	if smoke.Namespace != os.Getenv("ENVPILOT_RECONCILE_NAMESPACE") {
		return fmt.Errorf("ingress smoke namespace %q must match reconciler namespace", smoke.Namespace)
	}
	if smoke.Port == 0 || smoke.Host == "" {
		return fmt.Errorf("ingress smoke requires managed.smoke.host and managed.smoke.port")
	}
	className := dep.ExistingClassName
	if className == "" {
		className = "nginx"
	}
	gvr := schema.GroupVersionResource{Group: "networking.k8s.io", Version: "v1", Resource: "ingresses"}
	obj := map[string]any{
		"apiVersion": "networking.k8s.io/v1", "kind": "Ingress",
		"metadata": map[string]any{"generateName": "envpilot-platform-smoke-", "namespace": smoke.Namespace, "labels": map[string]any{"app.kubernetes.io/managed-by": "envpilot-platform-reconciler"}},
		"spec":     map[string]any{"ingressClassName": className, "rules": []any{map[string]any{"host": smoke.Host, "http": map[string]any{"paths": []any{map[string]any{"path": "/", "pathType": "Prefix", "backend": map[string]any{"service": map[string]any{"name": smoke.ServiceName, "port": map[string]any{"number": smoke.Port}}}}}}}}},
	}
	created, err := client.Resource(gvr).Namespace(smoke.Namespace).Create(ctx, &unstructured.Unstructured{Object: obj}, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("create ingress smoke probe: %w", err)
	}
	defer client.Resource(gvr).Namespace(smoke.Namespace).Delete(ctx, created.GetName(), metav1.DeleteOptions{})
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		current, err := client.Resource(gvr).Namespace(smoke.Namespace).Get(ctx, created.GetName(), metav1.GetOptions{})
		if err == nil {
			if status, ok := current.Object["status"].(map[string]any); ok {
				if entries, ok := status["loadBalancer"].(map[string]any); ok {
					if ingress, ok := entries["ingress"].([]any); ok && len(ingress) > 0 {
						return nil
					}
				}
			}
		}
		time.Sleep(time.Second)
	}
	return fmt.Errorf("ingress smoke probe did not receive a controller endpoint")
}

type getter struct {
	cfg       *rest.Config
	namespace string
}

func (g *getter) ToRESTConfig() (*rest.Config, error) { return g.cfg, nil }
func (g *getter) ToDiscoveryClient() (discovery.CachedDiscoveryInterface, error) {
	d, e := discovery.NewDiscoveryClientForConfig(g.cfg)
	if e != nil {
		return nil, e
	}
	return memory.NewMemCacheClient(d), nil
}
func (g *getter) ToRESTMapper() (meta.RESTMapper, error) {
	d, e := g.ToDiscoveryClient()
	if e != nil {
		return nil, e
	}
	r, e := restmapper.GetAPIGroupResources(d)
	if e != nil {
		return nil, e
	}
	return restmapper.NewDiscoveryRESTMapper(r), nil
}
func (g *getter) Namespace() (string, bool, error) { return g.namespace, false, nil }
func (g *getter) ToRawKubeConfigLoader() clientcmd.ClientConfig {
	return clientcmd.NewDefaultClientConfig(*clientcmdapi.NewConfig(), &clientcmd.ConfigOverrides{})
}
func helmApply(m managedConfig, restCfg *rest.Config) error {
	settings := cli.New()
	settings.SetNamespace(m.Namespace)
	var conf action.Configuration
	if err := conf.Init(&getter{cfg: restCfg, namespace: m.Namespace}, m.Namespace, "secret", log.Printf); err != nil {
		return err
	}
	path, err := (&action.ChartPathOptions{Version: m.Version}).LocateChart(m.ChartRef, settings)
	if err != nil {
		return err
	}
	ch, err := loader.Load(path)
	if err != nil {
		return err
	}
	values := map[string]any{}
	for key, value := range m.Values {
		values[key] = value
	}
	values["envpilotOwnership"] = "envpilot"
	get := action.NewGet(&conf)
	existing, getErr := get.Run(m.ReleaseName)
	if getErr == nil {
		if existing.Config["envpilotOwnership"] != "envpilot" {
			return fmt.Errorf("helm release %s exists but is not owned by envpilot", m.ReleaseName)
		}
		upgrade := action.NewUpgrade(&conf)
		upgrade.Namespace = m.Namespace
		upgrade.Wait = true
		_, err = upgrade.Run(m.ReleaseName, ch, values)
		return err
	}
	install := action.NewInstall(&conf)
	install.ReleaseName = m.ReleaseName
	install.Namespace = m.Namespace
	install.CreateNamespace = false
	install.Wait = true
	if _, err = install.Run(ch, values); err == nil {
		return nil
	}
	return err
}
func cleanup(cfg config, restCfg *rest.Config) error {
	for _, dep := range []capability{cfg.Ingress, cfg.DNS, cfg.Storage} {
		if dep.Mode == "managed" && dep.Ownership == "envpilot" && dep.Managed.CleanupPolicy == "delete" && dep.Managed.ReleaseName != "" {
			var conf action.Configuration
			if err := conf.Init(&getter{cfg: restCfg, namespace: dep.Managed.Namespace}, dep.Managed.Namespace, "secret", log.Printf); err != nil {
				return err
			}
			if _, err := action.NewUninstall(&conf).Run(dep.Managed.ReleaseName); err != nil {
				return err
			}
		}
	}
	return nil
}
func persistStatus(client kubernetes.Interface, statuses map[string]result) error {
	b, _ := json.Marshal(statuses)
	ns := os.Getenv("ENVPILOT_RECONCILE_NAMESPACE")
	name := os.Getenv("ENVPILOT_RECONCILE_STATUS_CONFIG_MAP")
	cm, err := client.CoreV1().ConfigMaps(ns).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		cm = &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: ns}, Data: map[string]string{"status.json": string(b)}}
		_, err = client.CoreV1().ConfigMaps(ns).Create(ctx, cm, metav1.CreateOptions{})
		return err
	}
	if cm.Data == nil {
		cm.Data = map[string]string{}
	}
	cm.Data["status.json"] = string(b)
	_, err = client.CoreV1().ConfigMaps(ns).Update(ctx, cm, metav1.UpdateOptions{})
	return err
}
