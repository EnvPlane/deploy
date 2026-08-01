// platform-reconciler is deliberately limited to external platform
// capabilities. It never installs EnvPilot core charts or workloads.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"helm.sh/helm/v3/pkg/action"
	"helm.sh/helm/v3/pkg/chart/loader"
	"helm.sh/helm/v3/pkg/cli"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
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
			res.State = "degraded"
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
	if err := helmApply(dep.Managed, restCfg); err != nil {
		return r, fmt.Errorf("managed %s provider: %w", name, err)
	}
	r.State = "managed"
	r.Ownership = "envpilot"
	return r, nil
}

func detect(name string, dep capability, client dynamic.Interface) (bool, string, error) {
	switch name {
	case "ingress":
		list, err := client.Resource(schema.GroupVersionResource{Group: "networking.k8s.io", Version: "v1", Resource: "ingressclasses"}).List(ctx, metav1.ListOptions{})
		if err != nil {
			return false, "", err
		}
		for _, item := range list.Items {
			if dep.ExistingClassName == "" || item.GetName() == dep.ExistingClassName {
				if c, ok := item.Object["spec"].(map[string]any); ok && c["controller"] != nil {
					return true, item.GetName(), nil
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
	install := action.NewInstall(&conf)
	install.ReleaseName = m.ReleaseName
	install.Namespace = m.Namespace
	install.CreateNamespace = false
	install.Wait = true
	ch, err := loader.Load(path)
	if err != nil {
		return err
	}
	if _, err = install.Run(ch, m.Values); err == nil {
		return nil
	}
	upgrade := action.NewUpgrade(&conf)
	upgrade.Namespace = m.Namespace
	upgrade.Wait = true
	_, err = upgrade.Run(m.ReleaseName, ch, m.Values)
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
