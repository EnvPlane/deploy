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

The supported same-cluster installation uses one immutable umbrella release;
`latest` is never a supported version selector:

<!-- envplane:canonical-install-command:start -->
```bash
helm upgrade --install envplane oci://ghcr.io/envplane/envplane \
  --version <published-umbrella-version> \
  --namespace envplane \
  --create-namespace \
  --wait
```
<!-- envplane:canonical-install-command:end -->

Helm prints the next step: run its `kubectl port-forward` command, then open
`http://127.0.0.1:3000` for first-run. For a preflight that only diagnoses the
cluster and writes a non-secret StorageClass override, run
`scripts/envplane-install-preflight.sh --version <published-umbrella-version>`.
See [`docs/installation.md`](docs/installation.md) for preflight, upgrade,
rollback and recovery commands.

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
