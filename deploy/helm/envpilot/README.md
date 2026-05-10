# EnvPilot umbrella chart

This chart installs the EnvPilot control-plane, cluster agent, and runner as one Helm release.

For a clean install with private GHCR images, provide:

- `registry.createPullSecret=true`
- `registry.username`
- `registry.password`
- `bootstrap.agent.registrationToken`
- `bootstrap.runner.registrationToken`
- `bootstrap.runner.projectConfigToken`
- `agent.cluster.id`
- `runner.project.clusterId`
- storage classes for Postgres, Redis, agent auth, and runner auth when the cluster has no default `StorageClass`

Build dependencies before installing from source:

```sh
helm dependency build deploy/helm/envpilot
```

Then install:

```sh
helm install envpilot deploy/helm/envpilot --namespace envpilot --create-namespace -f values.clean.yaml
```

Bootstrap tokens are one-time credentials. Agent and runner auth tokens are persisted on PVCs by default, so subsequent pod replacements do not reuse bootstrap tokens.
