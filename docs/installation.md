# EnvPilot installation

This is the supported production installation path for an already provisioned
Kubernetes cluster. EnvPilot is installed as one OCI umbrella release; it does
not provision a cluster or install a distribution-specific add-on.

## Prerequisites

The operator must provide:

- Kubernetes 1.26 or newer and Helm 3.14 or newer;
- a kubeconfig context with permission to create the release namespace and the
  explicitly enabled EnvPilot resources;
- a default StorageClass, or an explicitly configured storage dependency, when
  bundled PostgreSQL/Redis or persistence is enabled;
- an existing healthy Ingress controller, Gateway API implementation, DNS
  integration and/or storage provisioner when their mode is `existing`;
- image-pull access to GHCR (or a private registry Secret) for every enabled
  component;
- existing Secret references for external PostgreSQL/Redis, registry pulls and
  provider credentials. Secret values are never placed in Git, values files or
  bootstrap sessions.

The target cluster, ingress/DNS provider and database services are owned by the
platform team. EnvPilot only creates resources in its release namespace and
does not create tunnels, minikube profiles or cloud infrastructure.

## Quick start

Create `values.yaml` from one of the examples below, then run exactly:

```sh
helm upgrade --install envpilot oci://ghcr.io/envpilot/envpilot \
  --version <published-umbrella-version> \
  --namespace envpilot \
  --create-namespace \
  --values values.yaml \
  --wait
```

The chart installs the API and frontend by default. Enable same-cluster Agent
and Runner declaratively when required:

```yaml
agent:
  enabled: true
runner:
  enabled: true
global:
  envpilot:
    firstStartRegistration:
      mode: managed
      cluster: {id: management-cluster}
```

`managed` retains chart-generated registration material across upgrades.
`existing` consumes an operator-created Secret named by
`global.envpilot.firstStartRegistration.existingSecret`. Plaintext tokens must
never be put in values. Remote execution targets are configured after this
install through the authenticated UI/API RemoteCluster flow, not values or
manual child-chart commands. See [API-managed remote clusters](remote-clusters.md).

## Platform dependency modes

Each of `platformDependencies.ingress`, `.dns` and `.storage` has one mode:

| Mode | Meaning |
|---|---|
| `disabled` | EnvPilot does not require or manage this capability. |
| `existing` | Reuse a healthy, compatible capability without adoption or mutation. |
| `auto` | Detect a healthy capability first; install only an explicitly configured provider when absent. |
| `managed` | Install/upgrade the explicitly selected pinned provider chart, with explicit ownership and cleanup policy. |

`auto` and `managed` require the platform dependency reconciler and pinned
provider configuration. They never guess cloud credentials. `existing` requires
the class/provider/Secret references appropriate to that capability. A degraded
or scope-mismatched capability blocks dependent features and is reported in the
reconciler status ConfigMap.

Provider credentials are supplied only as `credentials.existingSecret` (DNS) or
provider chart values that reference an existing Secret. The reconciler reads
metadata and health, never prints Secret data.

## Values examples

### Generic Kubernetes (ClusterIP, existing storage)

```yaml
access: {mode: disabled}
platformDependencies:
  ingress: {mode: disabled}
  dns: {mode: disabled}
  storage: {mode: existing, existingClassName: standard}
```

### nginx Ingress

```yaml
access:
  mode: ingress
  ingress: {host: envpilot.example.test, className: nginx}
platformDependencies:
  ingress: {mode: existing, provider: nginx, existingClassName: nginx}
```

### AWS ALB

```yaml
access:
  mode: ingress
  ingress:
    host: envpilot.example.test
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internal
platformDependencies:
  ingress: {mode: existing, provider: aws-alb, existingClassName: alb}
```

AWS credentials and the AWS Load Balancer Controller remain platform-owned.

### Gateway API

```yaml
access:
  mode: gateway
  gateway:
    name: shared-gateway
    namespace: gateway-system
    sectionName: https
    hostnames: [envpilot.example.test]
```

### External PostgreSQL/Redis

```yaml
envpilot-control-plane:
  postgres:
    mode: external
    external: {existingSecret: envpilot-postgres-url, urlKey: database-url}
  redis:
    mode: external
    external: {existingSecret: envpilot-redis-url, urlKey: redis-url}
```

### Private registry

```yaml
global:
  envpilot:
    registry:
      mode: existing
      existingSecret: registry-credentials
```

This grants every enabled runtime workload pull access without changing the
release-selected images. Published umbrellas reject repository, tag or digest
overrides that conflict with their signed compatibility manifest. Mirror the
published immutable artifacts if required by your registry policy, then publish
a corresponding signed umbrella release; do not use `latest`.

## Upgrades, rollback and uninstall

Each published umbrella archive includes a signed compatibility manifest with
the exact immutable runtime image refs it selects. Do **not** use Helm
`--reuse-values` for umbrella upgrades: Helm would retain the old nested image
maps and silently keep the preceding release's digest.

Keep a durable operator values file (the same file used for installation) and
upgrade with the provided wrapper, which uses `--reset-values` and layers that
file over the new chart defaults:

```sh
scripts/upgrade-umbrella.sh \
  --release envpilot \
  --chart oci://ghcr.io/envpilot/envpilot \
  --version <new-published-umbrella-version> \
  --namespace envpilot \
  --operator-values values.yaml
```

This preserves operator configuration while applying the artifact pins signed
in the selected release. An explicit `envpilot-*.image` or
`platformDependencyReconciler.image` override that conflicts with the selected
manifest is rejected before Helm mutates the release; update it to the selected
immutable ref or remove it from the operator file. Do not put credentials in
the values file or generated release metadata.

Helm owns the core release and its child resources; external detected
capabilities are never adopted or deleted. Managed providers are removed only
when their configured ownership and cleanup policy permit it. Back up
database/PVC data before rollback or uninstall.

The repository's `scripts/minikube-*.sh` and clean-install scripts are retained solely for
automated test fixtures. They are not required for, or part of, the production
installation path.
