# EnvPilot chart

This is the single public EnvPilot Helm chart. It creates the EnvPilot namespace and runs `envpilot-install` as a Kubernetes Job in that namespace. The Job installs the EnvPilot control-plane, creates bootstrap secrets, seeds the default project/config, and installs the agent and runner.

Install:

```sh
helm install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.1.12 \
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

By default the chart creates and uses `installer.namespace=envpilot`.
The target application namespace is also `install.namespace=envpilot`.
Use an existing Helm release namespace such as `default`; the chart creates the
runtime namespace separately.

When `install.mode=clean-install`, the installer preserves the namespace that
contains its own Job and cleans EnvPilot releases, PVCs, and bootstrap secrets
inside it instead of deleting the namespace.

The Job needs cluster-admin-equivalent permissions because it creates/deletes namespaces, installs Helm releases, manages cluster roles, and execs into Postgres to seed the first project.

Published releases pin the API, frontend, Agent and Runner independently; do not
override them with a single shared image tag. The compatibility set is recorded
in `release/<chart-version>.yaml` in the deploy repository.

The installer passes `compatibility.apiContractVersion` to the control-plane.
The frontend checks `GET /api/v1/capabilities` before enabling optional
bootstrap actions such as demo/offline SCM mode. Do not override API or
frontend image tags with versions from different release manifests.

Deployment backend:

- `deployment.backend=helm_direct`: default, installs feature environments through Helm direct.
- `deployment.backend=fluxcd`: seeds project config for FluxCD/GitOps backend.
- `deployment.backend=argocd`: reserved for Argo CD, accepted as a planned value but installer exits with a clear not implemented error until the backend exists.

`registry.token` is used twice:

- As an image pull secret in the bootstrap namespace so Kubernetes can pull `ghcr.io/envpilot/install`.
- As `ENVPILOT_GHCR_TOKEN` inside the Job so `envpilot-install` can create the target namespace pull secret for EnvPilot application images.

## Local minikube install

For Docker-based minikube, do not advertise an Ingress hostname such as
`envpilot.local` unless a host-reachable ingress controller is part of the local
cluster setup. The supported one-chart local path exposes the Next.js frontend
as a NodePort; it proxies `/api` to the in-cluster control-plane service.

```sh
helm install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.1.12 \
  --namespace default \
  --set install.clusterId=envpilot \
  --set access.mode=nodeport \
  --set registry.token="$GHCR_TOKEN"

minikube -p envpilot service -n envpilot envpilot-control-plane-frontend --url
```

The second command prints the supported browser endpoint. Keep it running if
minikube reports that it is creating a tunnel. The install does not require an
Ingress addon, `/etc/hosts` entry, or a separate `minikube tunnel`.
