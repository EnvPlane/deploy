# Provider-neutral values contract

The umbrella chart has no Kubernetes-distribution, cloud, DNS, ingress
controller, domain, or StorageClass default. A base install exposes only
cluster-internal `ClusterIP` Services. Public access and provider integrations
must be selected explicitly in an environment values file.

## Component configuration

Each dependency has a top-level enablement switch and a canonical values block:

| Component | Enablement | Configuration |
|---|---|---|
| Control plane | `controlPlane.enabled` | `envpilot-control-plane.*` |
| Frontend | `frontend.enabled` | `envpilot-frontend.*` |
| Agent | `agent.enabled` | `envpilot-agent.*` |
| Runner | `runner.enabled` | `envpilot-runner.*` |

Every component block supports `image.repository`, `image.tag`, optional
`image.digest`, `image.pullPolicy`, `image.sourceRevision`, `image.release`,
`imagePullSecrets`, `resources`, `nodeSelector`, `tolerations`, `affinity`,
`podSecurityContext`, and `securityContext`. A tag is required when no digest is
set and `latest` is rejected. A digest takes precedence over a tag and renders
as `repository@sha256:...`. The rendered Pod annotations expose the resolved
image reference plus `envpilot.io/source-revision` and `envpilot.io/release` so
operators can trace a workload to its CI build without using mutable tags.

`envpilot-control-plane` and `envpilot-frontend` also expose a Kubernetes
`service` block (`type`, `port`, and frontend `nodePort` when intentionally
using that Service type). The control-plane, PostgreSQL, Redis, Agent and
Runner persistence blocks accept an empty `storageClassName`, so the target
cluster's default storage policy remains authoritative. Configure
`existingClaim` or an existing Secret where the child chart supports it rather
than embedding credentials in values.

### Private runtime registry

Use the shared registry contract when any pinned runtime or dependency image is
private. The Secret must already exist in the release namespace and contain a
standard `.dockerconfigjson`; the chart stores and renders only its name:

```yaml
global:
  envpilot:
    registry:
      mode: existing
      existingSecret: envpilot-registry
      preflight:
        enabled: true
```

The umbrella propagates this reference to every enabled child workload, Agent
and Runner helper Job/CronJob, and the platform reconciler. A pre-install and
pre-upgrade check mounts the referenced Secret and fails with its name if it is
missing or empty, before dependent workloads are rolled out. The chart never
creates a Secret from raw credentials and never logs registry data. Explicit
per-component `imagePullSecrets` remain supported and are merged without
duplicates.

Agent and Runner remain disabled by default. Enable them only with an existing
project-scoped registration Secret; values never need to contain a plaintext
bootstrap token.

### Browser authentication and default tenant membership

The local and production browser flow requires an operator-managed OAuth/OIDC
Secret. Configure only its name through `global.envpilot.auth.existingSecret`
(or `envpilot-control-plane.auth.existingSecret`). The Secret is read by the
control-plane through `secretKeyRef` and is never returned by the API or copied
into browser/session/audit state.

The Secret uses these keys when the corresponding provider is enabled:

- `oauth-session-secret` — random HMAC session key;
- `gitlab-client-id`, `gitlab-client-secret`;
- `github-client-id`, `github-client-secret`;
- `oidc-client-id`, `oidc-client-secret`.

Provider endpoint overrides are non-secret values under the child chart's
`auth.github`, `auth.gitlab`, or `auth.oidc` blocks. A successful OAuth callback
creates or restores the user's active membership in tenant `default`. Without
an active membership the frontend blocks quota-controlled mutations and links
to sign-in; it never relies on a hidden tenant header or a development bypass.

## Declarative same-cluster first start

One Helm release can create and register a same-cluster Agent and Runner without
an installer Job, port-forward, generated command, or bootstrap API call. Enable
the two child charts and select `global.envpilot.firstStartRegistration.mode`:

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

`managed` creates an opaque chart-owned Secret with three one-time credentials.
The template uses Helm `lookup` to retain those credentials during upgrades.
The control plane reads the Secret only at startup, creates the minimal project
and bootstrap-session identity if absent, and persists only credential hashes.
Agent and Runner exchange their credential for their normal persisted runtime
auth token. A restart does not reset a consumed credential; an unused expired
credential is renewed only when its Secret-derived hash is unchanged.

For an operator-managed Secret, select `mode: existing` and supply the Secret
name. It must provide `agent-registration-token`, `runner-registration-token`,
and `runner-project-config-token`; the chart does not render or log its values.

### Bootstrap Agent endpoint

For an Agent installed in the same cluster as the umbrella release, leave
`envpilot-control-plane.agentBootstrap.controlPlaneURL` empty. The control
plane then generates bootstrap instructions using its Kubernetes Service FQDN
(`http://envpilot-control-plane.<release-namespace>.svc:8080`), rather than a
browser ingress hostname. The generated preflight runs `agent-connectivity-check`
from the selected Agent image and does not consume the one-time registration
credential.

For API/UI-managed remote clusters, set the management umbrella’s explicit
stable private or public endpoint instead of a child-chart bootstrap override:

```yaml
global:
  envpilot:
    remoteControlPlane:
      endpoint: https://api.envpilot.example.test
      tls:
        # Optional private-CA reference. The named Secret/key must exist in
        # each remote Agent/Runner namespace; values contain no CA bytes.
        caSecretRef: {name: envpilot-remote-ca, key: ca.crt}
```

The endpoint may be private or public DNS, but must be target-pod-reachable
HTTPS. `localhost`,
`envpilot.local`, `host.minikube.internal`, port-forwards and Kubernetes
Service DNS are rejected. When this endpoint is served by this chart’s
Ingress, `access.ingress.tls.enabled=true` and its existing certificate
`secretName` are required. Gateway/API LoadBalancer certificate attachment
remains provider-owned. The one-time registration token remains only in the
separate bootstrap Secret path; no raw credential, CA or server certificate is
returned through the API.

The matching Agent chart is declared by
`envpilot-control-plane.agentBootstrap.chart.ref` and `.version`. The umbrella
release sets these from its `envpilot-agent` dependency, records the exact value
in its signed compatibility manifest, and the dependency-update workflow keeps
them together. A standalone control-plane chart has no implicit OCI chart
version: set both fields explicitly for a remote Agent contract.

```yaml
global:
  envpilot:
    firstStartRegistration:
      mode: existing
      existingSecret: platform-envpilot-first-start
      cluster:
        id: management-cluster
```

The same-cluster reconciler refuses a different credential for an already bound
identity. Rotate/reissue remains an explicit remote-cluster control-plane flow;
never replace a managed Secret as an implicit rotation mechanism.

## Public access

`access.mode` is one of:

| Mode | Rendered resource | Prerequisite |
|---|---|---|
| `disabled` | None | Default; Services remain internal. |
| `ingress` | `networking.k8s.io/v1` Ingress | An existing controller and `access.ingress.host`. |
| `gateway` | Gateway API `HTTPRoute` | An existing Gateway and `access.gateway.name`. |

The chart does not install an Ingress controller or Gateway. Provider-specific
annotations are permitted only under `access.ingress.annotations`; no provider
annotation is set by default.

Ingress example:

```yaml
access:
  mode: ingress
  ingress:
    host: envpilot.example.internal
    className: shared-ingress
    annotations:
      example.platform.io/owner: platform
```

Gateway example:

```yaml
access:
  mode: gateway
  gateway:
    name: shared-gateway
    namespace: gateway-system
    sectionName: https
    hostnames:
      - envpilot.example.internal
```

Set `access.services.controlPlaneName` and `access.services.frontendName` only
when overriding the child chart fullnames.

For direct service exposure, use the explicit `profiles/nodeport.yaml` or
`profiles/loadbalancer.yaml` overlays. The default remains `ClusterIP`; neither
profile installs a tunnel, cloud load balancer controller, or cluster add-on.

## Data and persistence

`envpilot-control-plane.postgres` and `.redis` use `enabled` as the legacy
internal/disabled switch. New values should use the explicit `mode`:

- `internal`: create the child chart's StatefulSet and optional PVC.
- `external`: do not render the StatefulSet; inject a complete connection URL
  from an existing Secret.
- `disabled`: do not render the StatefulSet or connection environment variable.

External data services example:

```yaml
envpilot-control-plane:
  postgres:
    mode: external
    external:
      existingSecret: envpilot-postgres-url
      urlKey: database-url
  redis:
    mode: external
    external:
      existingSecret: envpilot-redis-url
      urlKey: redis-url
```

Internal persistence has no named StorageClass default. Set a class only when
the target cluster requires one:

```yaml
envpilot-control-plane:
  postgres:
    persistence:
      storageClassName: fast-rwo
```

## Platform dependency intent

`platformDependencies.ingress`, `.dns`, and `.storage` each require an
explicit `mode`: `auto`, `managed`, `existing`, or `disabled`. They declare
platform intent and provider/Secret references without embedding a cloud or
Kubernetes-distribution assumption in chart defaults.

The direct umbrella consumes existing ingress/Gateway, DNS, and storage
capabilities. It does not silently install a platform provider. `auto` and
`managed` are handled only by the optional, scoped platform reconciler and
require explicit pinned provider configuration; otherwise select `existing` or
`disabled` and provision the platform outside EnvPlane.

The reconciler is disabled by default when no dependency mode is enabled. To
turn it on, set `platformDependencyReconciler.enabled=true` and provide either
the shared `global.envpilot.registry.mode=existing` Secret or explicit
`platformDependencyReconciler.imagePullSecrets`. Its pre-install/pre-upgrade
job is bounded; cleanup is opt-in, bounded by `cleanupDeadlineSeconds`, and
deletes failed hook Jobs so a missing image cannot leave a stale Job behind.

The umbrella renders the declared mode, provider, reference and state into a
non-secret ConfigMap and the control plane exposes it as
`GET /api/v1/capabilities.platformDependencies`. This is configuration status,
not a Kubernetes capability probe: EnvPlane never installs ingress controllers,
DNS integrations, StorageClasses, minikube add-ons, tunnels, or clusters.
Set an optional dependency `state` to `ready` or `unavailable` only when an
external platform reconciler owns that observation.

## Component RBAC

All component ServiceAccounts can be supplied by the platform with
`serviceAccount.create=false`, `serviceAccount.name=<existing-name>` and
`rbac.create=false`. In that mode EnvPlane renders neither the ServiceAccount
nor RBAC objects; the platform owns the binding.

The control plane has namespace-scoped `get` access to Secrets only, configured
through `envpilot-control-plane.rbac.secretReader.namespaces`. It has no
ClusterRole. Agent discovery is read-only; set
`envpilot-agent.rbac.discovery.scope=cluster` explicitly only when namespace
enumeration and cluster capability probes are required. `scope=namespace` uses
one Role/RoleBinding per configured namespace. Agent Secret discovery remains
off by default and requires `rbac.discovery.readSecrets=true`.

Runner discovery is read-only, while its feature-environment writer is a
namespace-scoped Role. Configure every writable feature namespace through the
Runner `featureEnvWriter` mode; EnvPlane never grants Runner cluster-wide write
permissions. All default pod renders use the Kubernetes Pod Security
Restricted baseline: non-root execution, RuntimeDefault seccomp and dropped
Linux capabilities.

## Migration from the 0.1 installer values

The former installer-Job chart used `images.*`, `registry.*`, `project.*`,
`install.*`, `access.nodePort`, and provider-specific control-plane ingress
defaults. They are not carried into the direct umbrella automatically.

| Old value | New value / action |
|---|---|
| `images.api.*` | `envpilot-control-plane.image.*` |
| `images.frontend.*` | `envpilot-frontend.image.*` |
| `images.agent.*` | `envpilot-agent.image.*` |
| `images.runner.*` | `envpilot-runner.image.*` |
| `registry.token` | Create Kubernetes image pull Secrets and reference them through each component's `imagePullSecrets`. |
| `project.endpointDomain`, `loadBalancerType`, `ingressAnnotations` | Choose `access.mode=ingress` or `gateway`; set host/class/annotations explicitly. |
| `storage.className` | Set the exact internal persistence `storageClassName` fields, or use external data services. |
| `postgres.password` | Prefer `envpilot-control-plane.postgres.auth.existingSecret`; the plaintext field exists only for compatibility. |
| `install.*`, `agentInstall.*`, `deployment.*` | Remove. Bootstrap and remote execution registration are explicit control-plane workflows. |

The 0.1 child-chart booleans `postgres.enabled` and `redis.enabled` remain
supported when `mode` is omitted. Use `mode` for every new values file.

Validate a converted file before upgrade:

```sh
helm dependency build --skip-refresh deploy/helm/envpilot
helm lint deploy/helm/envpilot -f values.yaml
helm template envpilot deploy/helm/envpilot -f values.yaml > rendered.yaml
```
