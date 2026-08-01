# Platform dependency reconciler

When `platformDependencyReconciler.enabled=true`, the umbrella renders a
pre-install/pre-upgrade hook Job running `platform-reconciler`. The binary uses
client-go for capability discovery and the Helm Go SDK for configured provider
charts; it never shells out to `helm` or `kubectl` and never installs EnvPilot
core charts.

The default discovery ClusterRole is read-only for IngressClass and
StorageClass. Provider installation permissions are supplied explicitly under
`managed.rbacRules`; no wildcard provider RBAC is generated. Provider chart
references and versions must be pinned. Existing healthy capabilities are
reported as `detected` and are never adopted or modified. Failed detection or
provider operations are persisted as `missing`, `incompatible` or `degraded`
status in the reconciler ConfigMap and cause the hook to retry/fail visibly.

Ingress providers are resolved through an extensible registry. The built-in
`nginx` and `ingress-nginx` entries require controller
`k8s.io/ingress-nginx` and the pinned
`oci://ghcr.io/ingress-nginx/ingress-nginx` chart. An IngressClass is not
healthy merely because it exists: a matching controller Service must have
ready Endpoints or EndpointSlices. Managed ingress can optionally create a
short-lived smoke Ingress to a configured test Service and requires the smoke
namespace to be the reconciler namespace. Existing classes with a different
controller are reported as incompatible, preventing class and release
collisions; healthy existing controllers are reused without adoption.

Storage detection requires both a configured or default StorageClass and an
available provisioner (a matching CSIDriver or healthy provisioner Deployment),
not merely a class object. The first managed provider is
`local-path-provisioner`, configured with the pinned
`oci://ghcr.io/rancher/local-path-provisioner` chart. Cloud CSI providers are
never inferred. Managed storage runs a short-lived PVC smoke test and removes
the claim after it reaches `Bound`; a failed or timed-out claim is reported as
`degraded` and must not be used to back bundled PostgreSQL or Redis.

The pre-delete hook runs cleanup only for managed providers with
`ownership: envpilot` and `managed.cleanupPolicy: delete`. External providers
are always retained. Re-running install/upgrade is idempotent: Helm SDK install
is attempted first and an existing owned release is upgraded with the same
pinned chart and values. The hook Job is recreated by Helm on each retry or
upgrade and has a bounded deadline/backoff.

## Provisioned-cluster E2E matrix

`deploy/helm/envpilot/tests/platform-dependency-matrix.sh` runs the same
umbrella release against contexts supplied in `PLATFORM_E2E_CONTEXT`, covering
`empty`, `existing`, `mixed` and `degraded` dependency fixtures. It verifies
the reconciler status ConfigMap, repeats `helm upgrade --install` for
idempotency, and uninstalls the umbrella release. Existing resources are never
adopted; managed resources are cleaned according to their ownership policy.
The degraded fixture is expected to fail the hook and must retain an actionable
diagnostic in the status ConfigMap.

The fast umbrella contract matrix is
`deploy/helm/envpilot/tests/umbrella-contract-matrix.sh`. It runs lint, Helm
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
`ENVPILOT_E2E_EXISTING_RESOURCES` and must survive uninstall.
