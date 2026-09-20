# Managed Runner cannot remove its exact preview namespace

## Observed

In isolated E2E on image `ghcr.io/envplane/envplane:0.4.328`, a tenant-scoped
Helm Direct deletion correctly queued the managed Runner, but cleanup failed
with Kubernetes RBAC `Forbidden`: the Runner ServiceAccount could get the
exact preview namespace but could not delete it.

## Expected

The Runner must remove an EnvPlane-owned preview namespace after the guarded
Helm cleanup. It must not gain authority over arbitrary namespaces.

## Implementation prompt

In the runner Helm chart, extend the existing ClusterRole that is limited by
`rbac.featureEnvWriter` exact `resourceNames` with the `delete` verb for
`namespaces`. Keep the exact name list, ownership checks in the runtime, and
all workload-resource permissions namespace-scoped. Add a chart-contract
assertion that verifies both the exact resource name and `get,delete` verbs.
