# EnvPilot Deploy

Deployment and release artifacts for EnvPilot.

## Scope

- Helm charts for control plane, agent, and runner.
- Local Docker Compose development deployment.
- Container Dockerfile baseline.
- Setup documentation.

## Source Origin

This repository was split from:

- `deploy/helm/*`
- `docker-compose.yml`
- root `Dockerfile`
- deployment setup docs

## Notes

Packaged chart archives (`*.tgz`) and local credentials are intentionally not copied. Build and package charts from source as part of release automation.
# EnvPilot clean install

Use the Go installer to deploy the control-plane, create bootstrap secrets, and
install the agent and runner without manual `kubectl create secret` steps.

Build:

```sh
go build -o bin/envpilot-install ./cmd/envpilot-install
```

Example for the AWS dev cluster:

```sh
bin/envpilot-install \
  -mode clean-install \
  -cluster-id aws-bethunder-dev-bethunder-dev-1-21 \
  -storage-class gp2 \
  -node-arch arm64 \
  -toleration-key pool \
  -toleration-value apps
```

The installer uses `gh auth token` for GHCR unless `-ghcr-token` or
`ENVPILOT_GHCR_TOKEN` is set.

## Published Helm charts

Charts are published as OCI artifacts in the `envpilot` GitHub account:

```text
oci://ghcr.io/envpilot/envpilot-init:0.1.0
oci://ghcr.io/envpilot/envpilot:0.1.0
oci://ghcr.io/envpilot/envpilot-control-plane:0.1.0
oci://ghcr.io/envpilot/envpilot-agent-chart:0.1.0
oci://ghcr.io/envpilot/envpilot-runner-chart:0.1.0
```

## Enterprise one-chart install

The recommended install path is the `envpilot-init` chart. It starts a Kubernetes
Job with the `ghcr.io/envpilot/install` image. The Job runs `envpilot-install`
inside the cluster and installs the control-plane, seeds the first project,
creates bootstrap secrets, and installs the agent and runner.

Install the init chart into a bootstrap namespace, not the target EnvPilot
namespace. This avoids deleting the installer Job during `clean-install`.

```sh
helm install envpilot-init oci://ghcr.io/envpilot/envpilot-init \
  --version 0.1.0 \
  --namespace envpilot-installer \
  --create-namespace \
  --set install.clusterId=aws-bethunder-dev-bethunder-dev-1-21 \
  --set storage.className=gp2 \
  --set scheduling.nodeArch=arm64 \
  --set scheduling.toleration.key=pool \
  --set scheduling.toleration.value=apps \
  --set registry.token="$GHCR_TOKEN"
```

Follow progress:

```sh
kubectl logs -n envpilot-installer job/envpilot-init -f
```

The init Job requires cluster-admin-equivalent permissions because it creates and
deletes namespaces, installs Helm releases, creates cluster roles, and seeds the
fresh control-plane database.
