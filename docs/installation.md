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
  --version 0.3.2 \
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
never be put in values. Remote execution targets use the explicit control-plane
registration/rotation workflow and are outside this same-cluster release.

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
envpilot-control-plane:
  image:
    repository: registry.example.test/envpilot/api
    tag: 0.1.0
  imagePullSecrets: [{name: registry-credentials}]
envpilot-frontend:
  image:
    repository: registry.example.test/envpilot/frontend
    tag: 0.1.0
  imagePullSecrets: [{name: registry-credentials}]
```

Use immutable digest references for production releases. Do not use `latest`.

## Upgrades, rollback and uninstall

Upgrade with the same umbrella command and a new pinned chart version. Helm
owns the core release and its child resources; external detected capabilities
are never adopted or deleted. Managed providers are removed only when their
configured ownership and cleanup policy permit it. Back up database/PVC data
before rollback or uninstall.

The repository's `scripts/minikube-*.sh` and clean-install scripts are retained solely for
automated test fixtures. They are not required for, or part of, the production
installation path.
