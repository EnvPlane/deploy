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

## Published Helm chart

EnvPilot is installed through one OCI Helm chart:

```text
oci://ghcr.io/envpilot/envpilot:0.1.0
```

## Enterprise one-chart install

The `envpilot` chart creates the `envpilot` namespace and starts a Kubernetes Job
there with the `ghcr.io/envpilot/install` image. The Job runs `envpilot-install`
inside the cluster and installs the control-plane, seeds the first project,
creates bootstrap secrets, and installs the agent and runner.

```sh
helm install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.1.0 \
  --namespace default \
  --set install.clusterId=aws-bethunder-dev-bethunder-dev-1-21 \
  --set storage.className=gp2 \
  --set scheduling.nodeArch=arm64 \
  --set scheduling.toleration.key=pool \
  --set scheduling.toleration.value=apps \
  --set registry.token="$GHCR_TOKEN"
```

Follow progress:

```sh
kubectl logs -n envpilot job/envpilot -f
```

By default:

- Helm release namespace: `default`
- installer job namespace: `envpilot`
- application namespace: `envpilot`

Because the install Job runs in the target namespace, `clean-install` preserves
the namespace and cleans EnvPilot Helm releases, PVCs, and bootstrap secrets
instead of deleting the namespace.

The installer Job requires cluster-admin-equivalent permissions because it creates and
deletes namespaces, installs Helm releases, creates cluster roles, and seeds the
fresh control-plane database.
