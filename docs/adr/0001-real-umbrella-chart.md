# ADR-0001: Real Helm umbrella chart with managed platform dependencies

**Status:** Proposed  
**Date:** 2026-07-31  
**Deciders:** EnvPilot maintainers  
**Repositories:** `deploy`, `control-plane`, `agent`, `runner`, `frontend`

## Context

The published `envpilot` chart is currently a bootstrap installer, not a Helm
umbrella chart. It renders a privileged post-install/post-upgrade Job using
`ghcr.io/envpilot/install`. That Job invokes `helm` and `kubectl`, installs the
control plane, Agent and Runner as separate Helm releases, creates bootstrap
credentials, and can clean namespaces and cluster-scoped RBAC.

This implementation has material operational drawbacks:

- the visible `helm install` succeeds before the actual application installation
  has completed;
- core workload ownership is spread over an umbrella release and nested releases;
- upgrade, rollback and uninstall have incomplete Helm lifecycle semantics;
- cluster-admin-like permissions are granted to an application installer;
- scripts and minikube-specific access paths are part of the supported install
  flow;
- it is difficult to produce one immutable release contract for API, frontend,
  Agent, Runner and their charts.

EnvPilot must support a provider-neutral installation in a pre-existing
Kubernetes cluster through exactly one command:

```sh
helm upgrade --install envpilot oci://ghcr.io/envpilot/envpilot \
  --version <version> \
  --namespace envpilot \
  --create-namespace \
  -f values.yaml
```

The product must not create, delete or otherwise provision a Kubernetes cluster.
It must, however, be able to verify and, when explicitly requested, install the
external capabilities required to expose and persist EnvPilot: an ingress
controller, DNS integration and dynamic StorageClass provisioner.

## Decision

### 1. `envpilot` becomes a real Helm v2 umbrella chart

`deploy/deploy/helm/envpilot/Chart.yaml` will declare canonical EnvPilot child
charts as Helm dependencies. The umbrella directly renders the core workload
resources and owns their lifecycle through one Helm release.

The same-cluster component graph is:

```text
helm upgrade --install envpilot
            |
            +-- envpilot umbrella release
                 |
                 +-- control-plane chart
                 |    +-- API Deployment
                 |    +-- optional PostgreSQL and Redis
                 |
                 +-- frontend chart
                 |
                 +-- agent chart        (optional; same cluster)
                 |
                 +-- runner chart       (optional; same cluster)
                 |
                 +-- platform dependency reconciler Job (optional exception)
                      +-- detect existing ingress/DNS/storage
                      +-- install only explicitly configured missing providers
```

The installer image, post-install installer Job, nested core Helm releases,
`kubectl` execution, seed scripts and wildcard installer RBAC are removed from
the supported install path.

`deploy/deploy/helm` is the canonical source tree for the umbrella and all child
charts. A child chart version is recorded in `Chart.yaml.dependencies` and
`Chart.lock`; runtime image references are configured through values.

### 2. Cluster provisioning is outside EnvPilot; platform capabilities are not

The Kubernetes cluster itself, its node pools, cloud account, IAM, DNS zones and
provider credentials are external prerequisites. EnvPilot never creates or
deletes a minikube profile, Kubernetes cluster, cloud load balancer account or
DNS zone.

The chart accepts explicit configuration for three platform capabilities:

```yaml
platformDependencies:
  ingress:
    mode: auto # auto | managed | existing | disabled
    provider: ingress-nginx
  dns:
    mode: existing
    provider: external-dns
  storage:
    mode: auto
    provider: local-path
```

Mode semantics are:

| Mode | Behaviour |
|---|---|
| `auto` | Detect a compatible healthy existing capability. Reuse it if found; otherwise install only the explicitly configured provider. |
| `managed` | Install or reconcile the explicitly configured provider. Existing unrelated resources are not adopted. |
| `existing` | Validate the explicitly named existing capability and fail if it is absent, incompatible or unhealthy. |
| `disabled` | Do not inspect or install the capability; dependent EnvPilot features must be disabled or use an alternative configured path. |

`auto` never guesses a cloud provider, DNS credentials, DNS zone, StorageClass
provisioner or IngressClass. If no compatible capability is found and required
provider configuration or credential Secret is missing, the release fails with a
precise diagnostic.

### 3. A narrowly scoped reconciler is the sole nested-install exception

Helm dependency conditions are evaluated during rendering and cannot be changed
after a pre-install lookup. Therefore a normal Helm dependency alone cannot both
detect an existing shared ingress/DNS/storage implementation and conditionally
install an upstream chart only when it is absent.

An optional chart-owned platform dependency reconciler Job is permitted solely
for this case. It uses the Kubernetes API and Helm Go SDK—not shell scripts and
not `helm`/`kubectl` executables—to:

1. discover capability objects and health;
2. classify them as `detected`, `managed`, `missing`, `incompatible` or
   `degraded`;
3. skip healthy existing implementations without Helm adoption;
4. install or upgrade only pinned, explicitly selected managed providers; and
5. record safe status in a namespaced status object without credentials.

The reconciler must never install API, frontend, Agent, Runner, PostgreSQL or
Redis. Those remain direct umbrella dependencies.

The supported initial providers are ingress-nginx, external-dns and
local-path-provisioner. Cloud CSI and cloud DNS providers are added only as
explicit adapters with documented identity/credentials and smoke tests.

### 4. Same-cluster and remote execution targets are distinct contracts

For same-cluster deployments, `agent.enabled` and `runner.enabled` include both
runtimes in the one umbrella release. The control plane exposes a cluster-local
endpoint; the chart supplies scoped registration material from either:

- a generated, upgrade-stable chart Secret; or
- an explicitly configured `existingSecret` managed by External Secrets, SOPS,
  Vault or the cluster operator.

The control plane exchanges registration material for component-specific runtime
credentials and persists only the safe resulting auth state. It idempotently
reconciles its installation and cluster identity on startup.

One Helm release cannot deploy workloads into a different Kubernetes API server.
Remote Agent/Runner are therefore intentionally separate published child-chart
installs. They use the existing project/cluster-scoped registration and
rotate/reissue flow; they are not represented as a dependency of the
same-cluster umbrella release.

```text
same cluster
  umbrella -> API + frontend + Agent + Runner

remote target cluster
  published envpilot-agent/envpilot-runner child chart
      -> HTTPS registration -> control-plane in management cluster
```

### 5. Secrets are references, never release inputs by default

Values contain Secret names and keys, not raw registry, SCM, DNS, cloud or
runtime tokens. Charts support `existingSecret` and image pull Secret references.
Generated same-cluster registration Secrets are mounted only into the exact API,
Agent and Runner workloads that require them; their values are never logged,
returned by API responses or stored in ConfigMaps.

An explicit unsafe local-development escape hatch, if retained, is disabled by
default and must be rejected by production policy tests. No normal release
documentation contains a credential literal.

### 6. Upgrade, rollback and uninstall follow declared ownership

| Operation | Core EnvPilot components | Existing platform capability | Managed platform capability |
|---|---|---|---|
| Upgrade | Helm upgrades child charts atomically after compatibility validation. | Observe only. | Reconcile only the provider/version declared in values. |
| Rollback | Helm restores the earlier immutable umbrella compatibility set. | No change. | Do not automatically downgrade a shared provider; report version skew and require an explicit platform action. |
| Uninstall | Delete resources owned by the umbrella release, subject to PVC retention policy. | Never delete or adopt. | Preserve by default; delete only with explicit `cleanupManaged=true` and matching installation ownership UID. |

The release manifest pins all component images by digest and child charts by
immutable version. API database migrations must remain backward compatible for
the documented N-1 -> N upgrade/rollback window; a migration that makes rollback
unsafe requires a separate data migration/runbook and cannot silently ship in an
umbrella patch release.

## Options considered

### Option A: Keep the installer Job and improve its scripts

| Dimension | Assessment |
|---|---|
| Complexity | Medium initially, high over time |
| Security | Poor: privileged in-cluster shell installer |
| Helm lifecycle | Poor: nested releases are not owned atomically |
| Portability | Low: scripts encode local/minikube behaviour |

**Pros:** Minimal immediate migration effort; existing API bootstrap endpoints
can remain unchanged.

**Cons:** Retains the fundamental ownership, rollback, privilege and
observability problems. It does not satisfy the one real umbrella-release
requirement.

### Option B: Direct umbrella dependencies plus scoped platform reconciler

| Dimension | Assessment |
|---|---|
| Complexity | Medium-high |
| Security | Good with bounded reconciler RBAC |
| Helm lifecycle | Good for core components; explicit policy for shared platform resources |
| Portability | High: provider adapters are selected through values |

**Pros:** One user-facing Helm command, direct ownership of EnvPilot workloads,
idempotent reuse of existing cluster capabilities, and a realistic route for
conditionally installing external platform dependencies.

**Cons:** Requires a small reconciler and provider adapter test matrix. Managed
platform dependencies are intentionally not rolled back automatically with the
application release.

### Option C: Require all platform dependencies to exist beforehand

| Dimension | Assessment |
|---|---|
| Complexity | Low |
| Security | Good |
| Helm lifecycle | Good |
| Portability | Medium: operator burden moves outside the chart |

**Pros:** Simple standard Helm dependencies and least privilege.

**Cons:** Does not meet the required install-if-missing behaviour and makes a
fresh supported cluster a multi-step/manual deployment.

### Option D: Deploy a permanent cluster-wide platform operator

| Dimension | Assessment |
|---|---|
| Complexity | High |
| Security | Medium: persistent cluster-level controller |
| Helm lifecycle | Medium: CRD/operator upgrade lifecycle required |
| Portability | High after substantial implementation work |

**Pros:** Rich reconciliation and asynchronous status.

**Cons:** Introduces a long-lived control plane and CRD surface solely for three
installation dependencies. It is disproportionate for the initial product
scope.

## Consequences

- `helm upgrade --install` becomes the only supported same-cluster application
  deployment path.
- Core EnvPilot components gain normal Helm ownership, readiness, rollback and
  uninstall semantics.
- Minikube is just one externally created Kubernetes cluster; chart defaults do
  not rely on it.
- Existing platform infrastructure is preserved and never silently adopted.
- A provider-aware capability contract becomes part of the public values API.
- The platform reconciler needs elevated but tightly scoped permissions and
  comprehensive tests for upgrades, collisions and cleanup.
- Remote cluster execution remains a deliberate separate release workflow;
  claiming one umbrella release can install into multiple clusters is incorrect.
- Image and child chart publishing must produce an atomic compatibility manifest
  before an umbrella release is published.

## Implementation constraints and guardrails

- No wildcard `apiGroups`, `resources` or `verbs` in the final core release RBAC.
- No core component may be installed by invoking Helm from a Job or controller.
- Existing ingress/DNS/storage resources must be detected by capability and health,
  not only by a resource name.
- DNS/cloud credentials are always supplied through existing Secrets or workload
  identity; they are never inferred or emitted by the chart.
- Storage validation includes a bounded dynamic PVC provisioning test; an existing
  `StorageClass` object alone is not evidence of readiness.
- Ingress validation includes a matching controller and ready endpoints; an
  orphaned `IngressClass` is not sufficient.
- Managed dependency cleanup is opt-in and ownership-UID guarded.
- Every provider adapter has render, integration and published-artifact tests.

## Action items

1. [ ] Complete `EP-UMB-02` through `EP-UMB-08` for canonical charts, direct
   umbrella dependencies, values, bootstrap, portability, RBAC and image refs.
2. [ ] Complete `EP-PLAT-01` through `EP-PLAT-06` for platform capability
   detection, reconciliation and the ingress/DNS/storage provider adapters.
3. [ ] Complete `EP-REL-01` through `EP-REL-06` for immutable cross-repository
   component and child-chart release propagation.
4. [ ] Complete `EP-TEST-01`, `EP-TEST-02` and `EP-DOC-01` before deprecating
   the current installer Job and clean-install scripts.

