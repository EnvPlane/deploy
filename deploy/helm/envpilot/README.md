# EnvPilot umbrella chart

`envpilot` is the supported same-cluster installation path. It is a Helm v2
umbrella chart: Helm directly renders and owns the enabled control-plane,
frontend, Agent and Runner child charts. It does not run an installer image,
nested Helm or `kubectl`, create or delete namespaces, or grant wildcard
installer RBAC.

Install the release into the namespace where EnvPilot workloads belong:

```sh
helm upgrade --install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.3.0 \
  --namespace envpilot \
  --create-namespace \
  -f values.yaml
```

The default values install the control-plane and browser frontend. Agent and
Runner are disabled until explicitly selected. For a first-start same-cluster
install, enable both and let the umbrella create a stable chart-managed Secret:

```yaml
agent:
  enabled: true
runner:
  enabled: true
global:
  envpilot:
    firstStartRegistration:
      mode: managed
      cluster:
        id: management-cluster
```

This is still one `helm upgrade --install` operation: the control plane creates
the minimal project/bootstrap identity at startup, while Agent and Runner use
the chart Secret only for their one-time registration exchange. To use an
operator-owned Secret instead, use `mode: existing` and `existingSecret`; see
[`VALUES.md`](VALUES.md). Never put plaintext registration, SCM, registry, or
cloud credentials in values.

Remote execution targets are not part of a same-cluster Helm release. Install
the published `envpilot-agent` or `envpilot-runner` chart in the remote cluster
with its project/cluster-scoped registration Secret.

## Values

The provider-neutral values contract and JSON schema are documented in
[`VALUES.md`](VALUES.md). Defaults do not select a Kubernetes provider,
IngressClass, DNS provider, hostname, StorageClass, or cloud integration.
Expose EnvPilot with an explicit `access.mode` (`ingress` or `gateway`) or keep
the default ClusterIP-only Services. Ready-to-use operator overlays live in
[`profiles/`](profiles/) for generic Kubernetes, nginx Ingress, AWS ALB,
Gateway API, NodePort, LoadBalancer, and externally managed data services.

| Values key | Purpose |
|---|---|
| `controlPlane.enabled` | Enable the API and its data-store resources. |
| `frontend.enabled` | Enable the separately packaged frontend child chart. |
| `agent.enabled` | Enable an Agent in the same cluster after configuring its existing Secret. |
| `runner.enabled` | Enable a Runner in the same cluster after configuring its existing Secret. |
| `access.*` | Optional provider-neutral `Ingress` or Gateway API `HTTPRoute`. |
| `envpilot-*.image.*` | Per-component immutable image reference and pull policy. |

The umbrella never creates or deletes Kubernetes clusters. Platform dependency
modes document whether ingress, DNS and storage are externally managed or
provided by a separate reconciler; see `VALUES.md` for the explicit
`auto|managed|existing|disabled` contract.

## Migration from the installer Job chart (0.1.x)

The previous `envpilot` chart installed a privileged Job which created nested
Helm releases. It must not be upgraded blindly from a different release
namespace: the old nested control-plane release owns its resources in the
workload namespace.

1. Back up the control-plane database/PVCs and save every existing component
   values file: `helm get values <release> -n <namespace> -a`.
2. Identify the workload namespace and nested control-plane release with
   `helm list -A`. In the standard installer layout it is release `envpilot` in
   namespace `envpilot`.
3. Uninstall only the outer installer-Job release. Its former `Namespace` has
   the Helm `keep` policy; verify the workload namespace and nested releases
   remain before continuing. This removes the obsolete Job and wildcard
   ClusterRole/ClusterRoleBinding.
4. Upgrade the nested control-plane release in its *workload namespace* to the
   umbrella chart. Use the migration overlay below so the existing frontend
   Deployment keeps its immutable selector and name.
5. Leave existing standalone Agent and Runner releases disabled in the umbrella
   initially. Rotate/reissue their credentials and migrate each only in a
   maintenance window; do not delete an auth PVC without a backup or a
   replacement credential.

`migration-values.yaml`:

```yaml
envpilot-control-plane:
  frontend:
    enabled: false
    serviceName: envpilot-control-plane-frontend

envpilot-frontend:
  enabled: true
  fullnameOverride: envpilot-control-plane-frontend
  legacyControlPlaneSelector: true

agent:
  enabled: false
runner:
  enabled: false
```

Then run:

```sh
helm upgrade envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.3.0 \
  --namespace envpilot \
  --reuse-values \
  -f migration-values.yaml
```

Review `helm diff` (when available), then validate API and frontend health
before migrating an execution target. The old Runner chart remains migratable
in place using the compatibility values documented in
[`../envpilot-runner/NOTES.txt`](../envpilot-runner/templates/NOTES.txt).
