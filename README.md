# EnvPlane Deploy

Canonical Helm charts, deployment automation, and end-to-end installation
fixtures for [EnvPlane](https://envplane.dev).

## What this repository owns

- EnvPlane umbrella and stable child charts.
- Same-cluster installation for control plane, frontend, Agent, and Runner.
- Remote-cluster lifecycle and compatibility-pinned runtime artifacts.
- Release automation and published OCI chart verification.
- Minikube and published-artifact end-to-end scenarios.

## Installation

The supported same-cluster installation uses one umbrella release:

```bash
helm upgrade --install envplane oci://ghcr.io/envpilot/envpilot \
  --version <version> \
  --namespace envplane \
  --create-namespace \
  -f values.yaml
```

The existing OCI coordinates are retained for compatibility with the current
release pipeline. Review values and use a versioned chart before installing.
See [`deploy/helm`](deploy/helm) and
[`docs/remote-clusters.md`](docs/remote-clusters.md) for configuration.

## Local validation

```bash
./scripts/minikube-up.sh
./scripts/minikube-verify.sh
./scripts/minikube-down.sh
```

Run published-artifact and remote-cluster scenarios only against disposable or
approved test environments.

## Related components

- [Control Plane](https://github.com/EnvPlane/control-plane)
- [Frontend](https://github.com/EnvPlane/frontend)
- [Agent](https://github.com/EnvPlane/agent)
- [Runner](https://github.com/EnvPlane/runner)
- [Webhook](https://github.com/EnvPlane/webhook)

## Security

Do not commit kubeconfigs, registry credentials, cloud keys, bootstrap tokens,
or production values. Release credentials belong in CI secrets.

## Status

Private EnvPlane deployment and release component under active development.
