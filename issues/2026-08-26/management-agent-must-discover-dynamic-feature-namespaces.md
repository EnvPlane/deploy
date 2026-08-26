# Management Agent misses dynamically created feature namespaces

## Observed

The Docker Desktop operator profile enables the same-cluster management Agent,
but inherits the child chart's safe namespace-scoped discovery default. The
rendered Agent receives `ENVPLANE_WATCH_NAMESPACES=default` and therefore does
not see `envplane-pr-*` namespaces that EnvPlane creates dynamically.

`pr-20260826-test-app-full-114` had a Ready Flux Kustomization and running
workloads, yet remained `Creating` in the UI because no Agent status report
could be produced for its namespace.

## Expected

The management-cluster operator profile must grant the Agent cluster-scoped
read discovery and leave the watch namespace list empty. The Agent must still
honour its excluded-system-namespaces list and report only namespaces bearing
the EnvPlane environment label.

## Acceptance criteria

- A same-cluster management installation can report lifecycle updates for a
  dynamically created `envplane-pr-*` namespace.
- No environment namespace must be enumerated manually in Helm values.
- Workload reads remain read-only and system namespaces remain excluded.
- Chart and profile tests cover this configuration contract.
