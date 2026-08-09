# EnvPlane Helm chart ownership and migration

`deploy/deploy/helm` is the only editable source for distributable EnvPlane
Helm charts. The published OCI names are stable:

| Component | Canonical source | OCI reference |
|---|---|---|
| Control plane API | `deploy/helm/envpilot-control-plane` | `oci://ghcr.io/envpilot/envpilot-control-plane` |
| Frontend | `deploy/helm/envpilot-frontend` | `oci://ghcr.io/envpilot/envpilot-frontend` |
| Agent | `deploy/helm/envpilot-agent` | `oci://ghcr.io/envpilot/envpilot-agent` |
| Runner | `deploy/helm/envpilot-runner` | `oci://ghcr.io/envpilot/envpilot-runner` |

`envpilot-runner-chart` is retired. Existing published versions remain
installable, but no new release is published under that OCI name. The copies
previously located in `runner/deploy/helm/envpilot-runner` and
`control-plane/charts/envpilot-runner` are removed; their former publishing
workflows no longer package charts.

## Runner migration

The retired chart used `envpilot-runner-chart` as both resource name and the
immutable Deployment selector. Preserve the running Deployment, RBAC and auth
PVC while switching to the canonical OCI chart:

```sh
helm upgrade <release> oci://ghcr.io/envpilot/envpilot-runner \
  --version <new-version> \
  --namespace <namespace> \
  --reuse-values \
  --set fullnameOverride=envpilot-runner-chart \
  --set legacyChartName=envpilot-runner-chart
```

Do not apply the two legacy settings to a new, second Runner release in the same
namespace. A later planned maintenance release may move an existing runner to
new resource names, but that requires creating a new auth PVC and is not part of
this compatibility migration.

### Legacy remote values without `controlPlane.tls`

Some Runner releases saved remote connection values before the optional
`controlPlane.tls` block existed. Upgrade those releases with `--reuse-values`;
the canonical chart treats the missing block as system trust and renders no CA
volume. Keep the remote endpoint explicit and stable:

```sh
helm upgrade <release> oci://ghcr.io/envpilot/envpilot-runner \
  --version 0.3.4 \
  --namespace <target-namespace> \
  --reuse-values \
  --set controlPlane.endpointMode=remote \
  --set controlPlane.url=https://api.envpilot.example.com
```

For a private CA, additionally set `controlPlane.tls.caSecret` and
`controlPlane.tls.caKey`; the Secret must already exist in the target namespace.
`localhost`, `host.minikube.internal`, Kubernetes Service DNS from another
cluster, and a developer `kubectl port-forward` are not supported remote
endpoints. The target Runner pod must be able to reach the configured URL after
the installer process exits.

## Control-plane frontend migration

`envpilot-control-plane` 0.2.0 consumes the canonical frontend chart as a local
dependency. Its defaults retain:

```yaml
frontend:
  fullnameOverride: envpilot-control-plane-frontend
  legacyControlPlaneSelector: true
  serviceName: envpilot-control-plane-frontend
```

Consequently an in-place upgrade from control-plane <= 0.1.x retains the
existing frontend Deployment and Service names and immutable selector. New
standalone frontend installations use the canonical chart's normal release-aware
resource name.

For a customised old control-plane `fullnameOverride`, set all three frontend
values to the corresponding old name before the upgrade:

```yaml
frontend:
  fullnameOverride: <old-control-plane-fullname>-frontend
  serviceName: <old-control-plane-fullname>-frontend
  legacyControlPlaneSelector: true
```

## Enforcement

`scripts/check-canonical-chart-sources.sh` is run by the publish workflows. It
rejects any core component chart source outside `deploy/deploy/helm`; it also
fails when an OCI chart name is duplicated. The embedded
`control-plane/charts/envpilot-smoke` fixture is not a distributable runtime
component and remains a documented exception until its runtime-bundle migration
is completed.
