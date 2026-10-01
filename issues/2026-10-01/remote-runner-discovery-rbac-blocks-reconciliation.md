# Remote Runner discovery RBAC blocks managed reconciliation

## Evidence

On EnvPlane `0.4.552`, a retry of the remote Flux namespace cleanup moved the
environment to `Terminating`, but the remote reconciler could not upgrade the
managed Runner release. Kubernetes rejected its attempt to patch the Runner
discovery Role and RoleBinding because the Role adds Flux API read access that
the reconciler identity does not hold.

The Runner performs Helm operations and namespace ownership checks. Flux
status is reported by the project Agent, so its default discovery Role does
not need `HelmRelease`, `Kustomization`, or `GitRepository` reads.

## Required implementation

1. Remove default Flux CRD read rules from both namespace-scoped and
   cluster-scoped Runner discovery roles.
2. Keep the explicit `featureEnvWriter.allowFluxResources` capability for
   deployments that intentionally render Flux resources.
3. Add a contract test proving managed remote Runner discovery does not
   contain Flux CRD read permissions.
4. Verify remote reconciliation can update the Runner without requiring the
   reconciler to escalate itself to Flux resource access.

## Codex implementation prompt

Constrain the Runner chart's discovery RBAC to resources consumed by Runner
runtime operations. Do not add permissions to the remote reconciler as a
workaround. Preserve the opt-in Flux writer capability and run the Runner
chart contract tests.
