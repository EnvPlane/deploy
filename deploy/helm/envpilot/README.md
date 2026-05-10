# EnvPilot chart

This is the single public EnvPilot Helm chart. It creates an installer namespace and runs `envpilot-install` as a Kubernetes Job. The Job installs the EnvPilot control-plane, creates bootstrap secrets, seeds the default project/config, and installs the agent and runner.

Install:

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
kubectl logs -n envpilot-installer job/envpilot -f
```

By default the chart creates and uses `installer.namespace=envpilot-installer`.
The target application namespace is `install.namespace=envpilot`.
Use an existing Helm release namespace such as `default`; the chart creates its
own installer namespace separately.

The Job needs cluster-admin-equivalent permissions because it creates/deletes namespaces, installs Helm releases, manages cluster roles, and execs into Postgres to seed the first project.

`registry.token` is used twice:

- As an image pull secret in the bootstrap namespace so Kubernetes can pull `ghcr.io/envpilot/install`.
- As `ENVPILOT_GHCR_TOKEN` inside the Job so `envpilot-install` can create the target namespace pull secret for EnvPilot application images.
