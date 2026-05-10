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
oci://ghcr.io/envpilot/envpilot:0.1.0
oci://ghcr.io/envpilot/envpilot-control-plane:0.1.0
oci://ghcr.io/envpilot/envpilot-agent-chart:0.1.0
oci://ghcr.io/envpilot/envpilot-runner-chart:0.1.0
```
