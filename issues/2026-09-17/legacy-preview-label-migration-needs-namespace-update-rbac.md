# Legacy preview label migration lacks namespace update RBAC

## Observed behavior

After upgrading the same-cluster Flux preview cleanup implementation, the
project Agent reports an empty or creating Flux status for a legacy preview
namespace. The control plane tries to add the missing
`envplane.io/environment-id` ownership label but receives Kubernetes `403`:

`system:serviceaccount:envplane:envplane-control-plane cannot update resource namespaces`.

## Root cause

The release-manager ClusterRole has `get`, `list`, `watch`, `create`, and
`delete` for `namespaces`, but not `update`. The legacy migration path is
deliberately ownership-scoped in application code, but its required Kubernetes
permission was omitted from the chart contract.

## Implementation prompt

Grant `update` only for `namespaces` in the existing same-cluster
release-manager ClusterRole. Keep the ownership and canonical-name checks in
the control plane. Bump the control-plane and umbrella chart versions, rebuild
the vendored dependency, and add a rendered-chart contract assertion.

## Acceptance criteria

- The control-plane ServiceAccount can update namespaces.
- It can label only namespaces that pass the same-cluster ownership checks.
- Flux cleanup resumes for a legacy canonical preview namespace.
- The chart contract fails if `update` is removed.
