# ADR-0001: Real Helm umbrella chart with managed platform and remote-cluster dependencies

**Status:** Proposed
**Date:** 2026-08-03
**Deciders:** EnvPlane maintainers
**Repositories:** `deploy`, `control-plane`, `agent`, `runner`, `frontend`

## Context

The published `envplane` chart is currently a bootstrap installer, not a Helm
umbrella chart. It renders a privileged post-install/post-upgrade Job using
`ghcr.io/envplane/install`. That Job invokes `helm` and `kubectl`, installs the
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

Remote target clusters currently require a user to run the published Agent and
Runner OCI charts manually. That makes the management UI unable to converge a
project's execution target, leaves bootstrap identities orphaned after failed
installs, and encourages unsupported endpoints such as an active local
port-forward or `host.minikube.internal`. A management-cluster Helm release
cannot directly own resources in another Kubernetes API server, but leaving
remote workload lifecycle outside the product is not an acceptable contract.

EnvPlane must support a provider-neutral installation in a pre-existing
Kubernetes cluster through exactly one command:

```sh
helm upgrade --install envplane oci://ghcr.io/envplane/envplane \
  --version <version> \
  --namespace envplane \
  --create-namespace \
  -f values.yaml
```

The product must not create, delete or otherwise provision a Kubernetes cluster.
It must, however, be able to verify and, when explicitly requested, install the
external capabilities required to expose and persist EnvPlane: an ingress
controller, DNS integration and dynamic StorageClass provisioner.

## Decision

### 1. `envplane` becomes a real Helm v2 umbrella chart

`deploy/deploy/helm/envplane/Chart.yaml` will declare canonical EnvPlane child
charts as Helm dependencies. The umbrella directly renders the core workload
resources and owns their lifecycle through one Helm release.

The same-cluster component graph is:

```text
helm upgrade --install envplane
            |
            +-- envplane umbrella release
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
                 |
                 +-- Remote Cluster Reconciler (bounded exception)
                      +-- read API/database desired state
                      +-- manage only remote Agent/Runner Helm releases
```

The installer image, post-install installer Job, nested core Helm releases,
`kubectl` execution, seed scripts and wildcard installer RBAC are removed from
the supported install path.

`deploy/deploy/helm` is the canonical source tree for the umbrella and all child
charts. A child chart version is recorded in `Chart.yaml.dependencies` and
`Chart.lock`; runtime image references are configured through values.

### 2. Cluster provisioning is outside EnvPlane; platform capabilities are not

The Kubernetes cluster itself, its node pools, cloud account, IAM, DNS zones and
provider credentials are external prerequisites. EnvPlane never creates or
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
| `disabled` | Do not inspect or install the capability; dependent EnvPlane features must be disabled or use an alternative configured path. |

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

One Helm release cannot render or own workloads in a different Kubernetes API
server. Remote Agent/Runner are therefore not umbrella dependencies and are not
configured through umbrella chart values. They are, however, product-managed
through an API/UI desired-state flow and the bounded reconciler defined below.

```text
same cluster
  umbrella -> API + frontend + Agent + Runner

remote target cluster
  UI/API RemoteCluster desired state -- Secret reference only --> database
                     |
                     v
       Remote Cluster Reconciler in management cluster
          | Kubernetes client + Helm Go SDK
          v
  remote API server -> Agent/Runner releases -> HTTPS control-plane endpoint
```

### 5. Remote Cluster Reconciler is the only cross-cluster release exception

The management-cluster control plane hosts a bounded Remote Cluster Reconciler.
It reads `RemoteCluster` and project-scoped Agent/Runner desired state from the
control-plane API/database, obtains remote Kubernetes access only from an
operator-provisioned referenced Secret, and uses Kubernetes clients plus the
Helm Go SDK to reconcile **only** the canonical `envplane-agent` and
`envplane-runner` releases in that remote cluster. It never shells out to
`helm` or `kubectl`.

Remote cluster configuration is created and changed through authenticated UI/API
resources, not `values.yaml`. Its API representation contains safe metadata
only: immutable cluster ID, display name, remote release namespace, an
`existingSecretRef` identifying management-cluster Secret name/key(s), optional
CA Secret reference, and a target-pod-reachable HTTPS control-plane endpoint.
The API never returns Secret data, bearer tokens, kubeconfig bytes, client keys,
or generated bootstrap tokens. Secret material is read by the reconciler under
least-privilege RBAC and is redacted from logs, events, audit payloads and
status responses.

The reconciler validates before it creates or upgrades a release:

1. the remote API endpoint, credentials and CA reference produce an authenticated
   remote Kubernetes client;
2. the configured control-plane URL is explicit HTTPS and passes a health/TLS
   preflight from the remote Agent/Runner Pod context;
3. the endpoint is not loopback, a port-forward address, `host.minikube.internal`,
   `envplane.local`, or a Kubernetes Service DNS name that belongs to another
   cluster; and
4. the selected immutable Agent/Runner chart and image compatibility set is
   available before reconciliation begins.

Same-cluster Service DNS is generated only for chart-managed same-cluster
Agent/Runner. A remote cluster must use a stable endpoint reachable by its own
Pods. The product never creates a tunnel, port-forward, Kubernetes cluster,
node pool, cloud account, DNS zone or cloud identity to satisfy this preflight.

Each managed remote release has labels and annotations containing the EnvPlane
management installation UID, remote-cluster ID, component, project identity and
desired-state generation. Reconciliation uses a database-backed per
`remoteCluster/component/project` lease with a bounded TTL and attempt ID.
Only the lease holder may call the remote API or Helm Go SDK; expired leases are
reported as retryable `degraded` state and may be safely reclaimed. The remote
Agent/Runner registration handshake remains project/cluster scoped, one-time
and rotation-capable. A newly issued credential invalidates its predecessor;
neither raw credential is persisted in desired state or returned after the
explicit one-time installation handoff.

Remote release lifecycle is deliberately narrow:

| Operation | Reconciler behaviour |
|---|---|
| Create/update | Validate desired state and preflight, then `upgrade --install` the canonical remote Agent or Runner with pinned chart/image references. |
| Retry/rotate | Keep the same release identity; rotate/reissue only via an authenticated, audited API action and reconcile a new Secret without exposing its value. |
| Rollback | Reconcile the prior immutable component compatibility set only after API/database compatibility validation; do not roll back feature environments. |
| Disable/uninstall | Remove only releases carrying the matching management ownership UID; revoke project-scoped credentials and retain safe audit/status history. |
| Lost access | Mark the remote cluster `degraded` with timestamp and recovery reason; do not fall back to the control-plane kubeconfig or another cluster. |

The reconciler has no authority to create user clusters, modify shared ingress,
DNS, StorageClasses, namespaces outside its owned Agent/Runner releases, or
operate feature-environment Helm releases. The target Runner remains the only
execution path for create/status/recreate/delete of an Environment.

Manual OCI installs migrate through an explicit audited import flow. The UI/API
first verifies the remote endpoint, release name, chart provenance, ownership
labels and project/cluster identity. Only a matching canonical release may be
adopted by recording an imported managed baseline; ambiguous or foreign releases
remain external and require an operator-directed replacement. The reconciler
never silently adopts a release or deletes a manually managed release during
migration.

### 6. Secrets are references, never release inputs by default

Values contain Secret names and keys, not raw registry, SCM, DNS, cloud or
runtime tokens. Charts support `existingSecret` and image pull Secret references.
Generated same-cluster registration Secrets are mounted only into the exact API,
Agent and Runner workloads that require them; their values are never logged,
returned by API responses or stored in ConfigMaps.

An explicit unsafe local-development escape hatch, if retained, is disabled by
default and must be rejected by production policy tests. No normal release
documentation contains a credential literal.

### 7. Upgrade, rollback and uninstall follow declared ownership

| Operation | Core EnvPlane components | Existing platform capability | Managed platform capability | Remote Agent/Runner |
|---|---|---|---|---|
| Upgrade | Helm upgrades child charts atomically after compatibility validation. | Observe only. | Reconcile only the provider/version declared in values. | Reconciler applies the matching immutable remote component set under its lease. |
| Rollback | Helm restores the earlier immutable umbrella compatibility set. | No change. | Do not automatically downgrade a shared provider; report version skew and require an explicit platform action. | Reconcile an API-approved prior remote compatibility set; preserve Runner-owned feature releases. |
| Uninstall | Delete resources owned by the umbrella release, subject to PVC retention policy. | Never delete or adopt. | Preserve by default; delete only with explicit `cleanupManaged=true` and matching installation ownership UID. | Delete only matching reconciler-owned Agent/Runner releases, revoke their identities and never delete a remote cluster or shared dependency. |

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

**Pros:** One user-facing Helm command, direct ownership of EnvPlane workloads,
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

### Option E: Keep remote Agent/Runner installation entirely manual

| Dimension | Assessment |
|---|---|
| Complexity | Low initially, high operationally |
| Security | Medium: credentials and command drift become operator responsibilities |
| Lifecycle | Poor: no API/UI convergence or bounded recovery |
| Portability | Medium: every cluster needs undocumented local knowledge |

**Pros:** Does not require remote Kubernetes client handling in the control
plane.

**Cons:** Fails the product-managed multi-cluster setup requirement, cannot
reliably recover stale identities, and encourages unsupported port-forward and
local DNS endpoint workarounds.

## Consequences

- `helm upgrade --install` becomes the only supported same-cluster application
  deployment path.
- Core EnvPlane components gain normal Helm ownership, readiness, rollback and
  uninstall semantics.
- Minikube is just one externally created Kubernetes cluster; chart defaults do
  not rely on it.
- Existing platform infrastructure is preserved and never silently adopted.
- A provider-aware capability contract becomes part of the public values API.
- The platform reconciler needs elevated but tightly scoped permissions and
  comprehensive tests for upgrades, collisions and cleanup.
- The umbrella remains exactly one management-cluster Helm release; remote
  Agent/Runner lifecycle is converged through an API/UI desired-state reconciler
  rather than through values or cross-cluster Helm ownership.
- Management-cluster credentials for remote API access are a sensitive external
  prerequisite and require secret-reference, audit and rotation controls.
- Remote endpoint reachability becomes a precondition for project readiness;
  unsupported local or foreign-cluster endpoint patterns fail early with an
  actionable diagnostic.
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
- Remote Kubernetes credentials, CA bundles and bootstrap tokens are accepted
  only through Secret references; no raw secret may enter values, API responses,
  audit records, reconcile status or logs.
- The Remote Cluster Reconciler may manage only labelled canonical Agent/Runner
  releases and must use per-target leases, attempt IDs and bounded timeouts.
- A remote target endpoint must be pod-reachable HTTPS. Port-forwards,
  `host.minikube.internal`, loopback and foreign Service DNS are rejected.
- Remote reconciliation may not use the control-plane kubeconfig as an
  Environment execution fallback.

## Action items

1. [ ] Complete `EP-UMB-02` through `EP-UMB-08` for canonical charts, direct
   umbrella dependencies, values, bootstrap, portability, RBAC and image refs.
2. [ ] Complete `EP-PLAT-01` through `EP-PLAT-06` for platform capability
   detection, reconciliation and the ingress/DNS/storage provider adapters.
3. [ ] Complete `EP-REL-01` through `EP-REL-06` for immutable cross-repository
   component and child-chart release propagation.
4. [ ] Complete `EP-TEST-01`, `EP-TEST-02` and `EP-DOC-01` before deprecating
   the current installer Job and clean-install scripts.
5. [ ] Add `EP-REMOTE-01` through `EP-REMOTE-07` for API/UI remote-cluster
   desired state, Secret references, endpoint preflight, reconciler leases,
   managed-release migration, lifecycle recovery and two-cluster E2E coverage.
