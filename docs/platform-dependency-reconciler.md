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

The pre-delete hook runs cleanup only for managed providers with
`ownership: envpilot` and `managed.cleanupPolicy: delete`. External providers
are always retained. Re-running install/upgrade is idempotent: Helm SDK install
is attempted first and an existing owned release is upgraded with the same
pinned chart and values. The hook Job is recreated by Helm on each retry or
upgrade and has a bounded deadline/backoff.
