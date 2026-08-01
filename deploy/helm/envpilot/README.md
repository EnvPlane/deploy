# EnvPilot umbrella chart

The production installation is the published OCI umbrella chart and one
`helm upgrade --install` command. Start with [`docs/installation.md`](../../../docs/installation.md)
for prerequisites, dependency modes, credentials and provider examples.

The umbrella directly owns the enabled control-plane, frontend, Agent and
Runner child charts. It does not run an installer image, nested Helm or
`kubectl`, create clusters, install minikube add-ons, or create/delete
namespaces outside the release namespace.

The repository-local `scripts/minikube-*.sh`, `scripts/*clean-install*.sh` and
published-artifact E2E harnesses are test fixtures only. They are not supported
production installation steps and must not be copied into an operator's
runbook.

For the values contract and migration details see [`VALUES.md`](VALUES.md).

## Migration from the installer Job chart

Migration guidance for 0.1.x releases is retained in the historical chart
documentation and must be reviewed before moving an existing release. Do not
use the retired installer Job or nested child releases for new installations.
The migration operation remains an explicit `helm upgrade envpilot` with a
reviewed migration values file.

That overlay may preserve a legacy frontend selector when required:

```yaml
envpilot-frontend:
  legacyControlPlaneSelector: true
```

Back up the existing Runner auth PVC before migration; the auth PVC must not be
deleted as part of a chart transition.

The migration removes the obsolete installer Job and its wildcard
ClusterRole/ClusterRoleBinding; it does not remove detected platform resources.

The old installer granted wildcard
   ClusterRole/ClusterRoleBinding permissions; the umbrella does not.
