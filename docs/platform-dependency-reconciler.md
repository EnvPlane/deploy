# Platform dependency reconciler

When `platformDependencyReconciler.enabled=true`, the umbrella renders normal,
release-owned ConfigMaps, ServiceAccount and RBAC plus bounded
post-install/post-upgrade hook Jobs running `platform-reconciler`. The binary uses
client-go for capability discovery and the Helm Go SDK for configured provider
charts; it never shells out to `helm` or `kubectl` and never installs EnvPlane
core charts.

The default discovery ClusterRole is read-only for IngressClass and
StorageClass. Provider installation permissions are supplied explicitly under
`managed.rbacRules`; no wildcard provider RBAC is generated. Provider chart
references and versions must be pinned. Existing healthy capabilities are
reported as `detected` and are never adopted or modified. Failed detection or
provider operations are persisted as `missing`, `incompatible` or `degraded`
status in the reconciler ConfigMap and cause the bounded hook to retry/fail
visibly. Hook Jobs delete themselves after success or failure; their support
resources are ordinary Helm manifests and are removed on uninstall.

Ingress providers are resolved through a pinned registry. `traefik` uses
IngressClass controller `traefik.io/ingress-controller` and chart
`oci://ghcr.io/traefik/helm/traefik` version `41.7.1` with package SHA-256
`43bcdc4302f627fcce94316e810b674fc8033112860462cc5f2127ff2f6042d8`.
Its OCI manifest digest is a separate value and is not a substitute for the
downloaded package checksum. The legacy `nginx` and `ingress-nginx` entries
still use controller `k8s.io/ingress-nginx` and the pinned upstream chart
`4.11.0`; they are not selected for an explicit Traefik dependency.

For an existing Traefik installation, set
`platformDependencies.ingress.mode=existing`, `provider=traefik`,
`namespace=traefik`, and `existingClassName=traefik` (adjust the last two to
the actual installation). The reconciler requires the exact class controller,
a Traefik-labelled Service and matching available Deployment whose selectors
identify the same installation in that namespace, and a ready EndpointSlice
or legacy Endpoints address for that
Service. A mismatched or orphaned named class fails without installing a
replacement. Existing releases are reused without adoption. Managed provider
configuration must match the registered chart URL, version and package SHA;
Traefik also requires a declared namespace and class. The operator supplies
`managed.rbacRules` for the reviewed chart's installation permissions; the
nginx-specific installer role is not granted to Traefik. Managed ingress can
optionally create a short-lived smoke Ingress to a configured test Service;
its namespace must be the reconciler namespace.

For a managed nginx migration, first record the current Helm release owner,
class, routes and TLS behavior. Install Traefik as a separately owned platform
release with a distinct class, verify a representative route and certificate,
then change the application Ingress class and the dependency contract to the
existing Traefik provider in a reviewed upgrade. Remove nginx only after its
routes no longer serve traffic and its owner has approved removal. Changing
`provider` alone never transfers Helm ownership, renames a release or removes
the old controller.

Storage detection requires both a configured or default StorageClass and an
available provisioner (a matching CSIDriver or healthy provisioner Deployment),
not merely a class object. The first managed provider is
`local-path-provisioner`, configured with the pinned
`oci://ghcr.io/rancher/local-path-provisioner` chart. Cloud CSI providers are
never inferred. Managed storage runs a short-lived PVC smoke test and removes
the claim after it reaches `Bound`; a failed or timed-out claim is reported as
`degraded` and must not be used to back bundled PostgreSQL or Redis.

The pre-delete hook runs cleanup only for managed providers with
`ownership: envplane` and `managed.cleanupPolicy: delete`. External providers
are always retained. Re-running install/upgrade is idempotent: Helm SDK install
is attempted first and an existing owned release is upgraded with the same
pinned chart and values. The hook Job is recreated by Helm on each retry or
upgrade and has a bounded deadline/backoff. Interrupted uninstalls are safe to
retry: Helm retains its release-owned support resources until pre-delete cleanup
finishes, then removes them. Existing registry Secrets and detected/external
providers are never adopted or deleted.

The reconciler's observed-status ConfigMap is release-owned but
**revision-scoped** by default (`<release>-platform-dependency-reconciler-status-r<revision>`).
The post-upgrade Job writes only to that fresh object. This avoids a
server-side-apply conflict with a previous Job's `status.json` field while
keeping each observed status constrained by named RBAC and removed by Helm on
upgrade/uninstall. An explicitly configured
`global.envplane.platformDependencyStatus.statusConfigMapName` is an
operator-owned external map and is not created by the umbrella.

The signed remote-cluster compatibility manifest follows the same lifecycle:
each enabled remote reconciler revision gets a new immutable
`<release>-remote-cluster-compatibility-r<revision>` ConfigMap. The control
plane mounts that exact name, so Helm never attempts to mutate an immutable map
in place. Rollback recreates the predecessor's immutable input rather than
rewriting the newer one.

Releases created before the support-resource ownership change may have
hook-created ConfigMaps, ServiceAccounts or RBAC left behind. On the next
install or upgrade the chart performs a bounded migration only when it detects
one of those named objects without the Helm ownership label. It removes that
legacy support object before rendering its normal replacement. The migration
never reads, deletes or adopts registry Secrets, IngressClasses, or detected
external providers.

## Provisioned-cluster E2E matrix

`deploy/helm/envplane/tests/platform-dependency-matrix.sh` runs the same
umbrella release against contexts supplied in `PLATFORM_E2E_CONTEXT`, covering
`empty`, `existing`, `mixed` and `degraded` dependency fixtures. It verifies
the reconciler status ConfigMap, repeats `helm upgrade --install` for
idempotency, and uninstalls the umbrella release. Existing resources are never
adopted; managed resources are cleaned according to their ownership policy.
The degraded fixture is expected to fail the hook and must retain an actionable
diagnostic in the status ConfigMap.

The fast umbrella contract matrix is
`deploy/helm/envplane/tests/umbrella-contract-matrix.sh`. It runs lint, Helm
JSON-schema validation, template policy checks and kubeconform for Kubernetes
1.26, 1.29 and 1.32 across minimal, all-enabled, external database, Ingress,
Gateway API, private registry and existing-secret profiles. It is intentionally
cluster-free and does not provision minikube.

## Published-artifact product E2E

`scripts/published-artifact-e2e.sh` accepts an already provisioned Kubernetes
context plus published N-1/N chart references and a values file. It performs
one initial `helm upgrade --install`, verifies API and UI health, same-cluster
Agent/Runner readiness, project/environment creation and terminal Runner
execution, then exercises upgrade, rollback and uninstall ownership. Port
forwarding is test-harness-only; the chart has no cluster-provider or minikube
special cases. Existing dependency resources can be listed with
`ENVPLANE_E2E_EXISTING_RESOURCES` and must survive uninstall.

`scripts/published-configmap-upgrade-e2e.sh` is the focused published N-1 to N
regression. It runs a server-side Helm upgrade, simulates a reconciler-owned
observed status field, verifies revision-scoped status and immutable
compatibility ConfigMaps, then verifies rollback and uninstall without conflict
overrides or manual ConfigMap deletion.
