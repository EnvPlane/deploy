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

For a local minikube clean install, `scripts/envpilot-clean-install.sh` selects
NodePort access and starts a `minikube service` tunnel for the frontend. It
prints a browser URL after checking that the page responds. Override
`ENVPILOT_MINIKUBE_PROFILE` when the active kubectl context is not the profile
name, or set `ENVPILOT_FRONTEND_ACCESS_MODE=ingress` on a cluster with a
host-reachable ingress controller. If the tunnel cannot start, the installer
prints the exact `minikube service ... --url` recovery command instead of
leaving a dead `envpilot.local` hostname.

## Published Helm chart

EnvPilot is installed through one OCI Helm chart:

```text
oci://ghcr.io/envpilot/envpilot:0.1.13
```

## Enterprise one-chart install

The `envpilot` chart creates the `envpilot` namespace and starts a Kubernetes Job
there with the `ghcr.io/envpilot/install` image. The Job runs `envpilot-install`
inside the cluster and installs the control-plane, seeds the first project,
creates bootstrap secrets, and installs the agent and runner.

```sh
helm install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.1.13 \
  --namespace default \
  --set install.clusterId=aws-bethunder-dev-bethunder-dev-1-21 \
  --set storage.className=gp2 \
  --set scheduling.nodeArch=arm64 \
  --set scheduling.toleration.key=pool \
  --set scheduling.toleration.value=apps \
  --set deployment.backend=helm_direct \
  --set registry.token="$GHCR_TOKEN"
```

Follow progress:

```sh
kubectl logs -n envpilot job/envpilot -f
```

### Local minikube endpoint

For a Docker-based local minikube profile, select the NodePort access contract
instead of assuming `envpilot.local` is host-reachable:

```sh
helm install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.1.13 \
  --namespace default \
  --set install.clusterId=envpilot \
  --set access.mode=nodeport \
  --set registry.token="$GHCR_TOKEN"

minikube -p envpilot service -n envpilot envpilot-control-plane-frontend --url
```

The returned frontend URL is the supported browser endpoint and proxies `/api`
to the control plane. It requires neither an `/etc/hosts` entry nor
`minikube tunnel`.

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

## Runner bootstrap recovery

If a target runner reports `stale_bootstrap_identity`, rotate its bootstrap
credentials in the project Bootstrap screen, apply the newly generated Secret
command, then run the generated `helm upgrade --install` command for the same
release. The runner stays live but unready while awaiting this recovery; do not
delete its auth PVC. The replacement registration token safely supersedes the
persisted runner auth token on the next rollout.

## GitHub Actions publishing

Pushes to `main` publish the deploy installer image and all charts from this
repository automatically. The installer image is published with `main`,
`latest`, and immutable `sha-*` tags:

```text
ghcr.io/envpilot/install
```

OCI chart versions use the source chart version plus the workflow run number,
for example `0.1.10-main.42`, so every main build is immutable. The workflow
uses the repository `GITHUB_TOKEN` by default; configure the organisation
`GHCR_TOKEN` secret when package write permissions are not granted to the
workflow token.
