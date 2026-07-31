# EnvPilot chart

This is the single public EnvPilot Helm chart. It creates the EnvPilot namespace and runs `envpilot-install` as a Kubernetes Job in that namespace. The Job installs the EnvPilot control-plane, creates bootstrap secrets, seeds the default project/config, and installs the agent and runner.

Install:

```sh
helm install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.1.17 \
  --namespace default \
  --set install.clusterId=aws-bethunder-dev-bethunder-dev-1-21 \
  --set project.loadBalancerType=alb \
  --set project.endpointDomain=tools.int \
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

The published chart defaults to the documented local browser URL
`http://envpilot.local` through an nginx IngressClass. Enable the minikube ingress
addon first.

For Docker-driver minikube, keep a privileged tunnel running and map
`envpilot.local` to `127.0.0.1`. For VM-driver minikube, `envpilot.local` can
resolve to `minikube -p envpilot ip`.

```sh
minikube -p envpilot addons enable ingress
# Docker-driver path:
minikube -p envpilot tunnel
# Ensure /etc/hosts contains: 127.0.0.1 envpilot.local

helm install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.1.17 \
  --namespace default \
  --set install.clusterId=envpilot \
  --set registry.token="$GHCR_TOKEN"
```

If local ingress is not available, use the explicit NodePort fallback:

```sh
helm upgrade --install envpilot oci://ghcr.io/envpilot/envpilot \
  --version 0.1.17 \
  --namespace default \
  --set install.clusterId=envpilot \
  --set access.mode=nodeport \
  --set registry.token="$GHCR_TOKEN"

minikube -p envpilot service -n envpilot envpilot-control-plane-frontend --url
```
