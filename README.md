# EnvPilot Deploy

The `deploy/deploy/helm` directory is the canonical source of EnvPilot's Helm
charts. The supported same-cluster installation is one real umbrella release:

```sh
helm upgrade --install envpilot oci://ghcr.io/envpilot/envpilot \
  --version <version> \
  --namespace envpilot \
  --create-namespace \
  -f values.yaml
```

The umbrella directly owns enabled control-plane, frontend, Agent and Runner
workloads. It does not publish or run a privileged `envpilot/install` image,
does not invoke nested Helm or `kubectl`, and does not delete namespaces.

The stable OCI child charts are:

- `oci://ghcr.io/envpilot/envpilot-control-plane`
- `oci://ghcr.io/envpilot/envpilot-frontend`
- `oci://ghcr.io/envpilot/envpilot-agent`
- `oci://ghcr.io/envpilot/envpilot-runner`

See the [umbrella chart guide](deploy/helm/envpilot/README.md) and the
[provider-neutral values contract](deploy/helm/envpilot/VALUES.md) for values,
same-cluster versus remote Agent/Runner operation, and migration from the
retired installer-Job chart. Chart ownership and child-chart migration details
are documented in [Helm chart ownership](docs/helm-chart-ownership.md).
