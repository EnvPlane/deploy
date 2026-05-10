# EnvPilot init chart

This chart runs `envpilot-install` as a Kubernetes Job. The client installs one chart, and the Job installs the EnvPilot control-plane, creates bootstrap secrets, seeds the default project/config, and installs the agent and runner.

Install the init chart into a bootstrap namespace, not the target EnvPilot namespace:

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

The Job needs cluster-admin-equivalent permissions because it creates/deletes namespaces, installs Helm releases, manages cluster roles, and execs into Postgres to seed the first project.

`registry.token` is used twice:

- As an image pull secret in the bootstrap namespace so Kubernetes can pull `ghcr.io/envpilot/install`.
- As `ENVPILOT_GHCR_TOKEN` inside the Job so `envpilot-install` can create the target namespace pull secret for EnvPilot application images.
