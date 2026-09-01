# envplane deploy

Install envplane on an existing Kubernetes cluster with one immutable umbrella
chart. No registration, Secret, values file, or manual child-chart assembly is
required for the default path.

## Quick start

Prerequisites: Kubernetes 1.26+, Helm 3.14+, a default StorageClass, namespace
RBAC, and anonymous access to `ghcr.io`.

<!-- envplane:canonical-install-command:start -->
```bash
helm upgrade --install envplane oci://ghcr.io/envplane/envplane --version 0.4.145 --namespace envplane --create-namespace --wait
```
<!-- envplane:canonical-install-command:end -->

<!-- envplane:stable-release-links:start -->
Stable release: `0.4.145` · [versioned installation guide](https://github.com/envplane/deploy/blob/37109f27ca16961cc56a8fd040f065c2627c5da2/docs/installation.md) · [guided installer](https://envplane-install.alexandr928857.chatgpt.site/install)
<!-- envplane:stable-release-links:end -->

Then verify the workloads and open first-run:

```bash
kubectl -n envplane rollout status deployment/envplane-control-plane --timeout=10m
kubectl -n envplane rollout status deployment/envplane-frontend --timeout=10m
kubectl -n envplane port-forward svc/envplane-frontend 3000:3000
```

Open <http://127.0.0.1:3000>. The first-run screen creates the initial owner and
authentication configuration. Installation starts on the built-in free plan;
activation or an offline license can be added later.

Read the [installation guide](docs/installation.md) for first-run, free limits,
activation, upgrades, uninstall, and troubleshooting. Production hardening,
private registries, external databases, remote clusters, ingress, and storage
selection are in [advanced installation](docs/installation-advanced.md).

## Repository ownership

- Umbrella and stable child charts.
- Same-cluster control plane, frontend, Agent, and Runner installation.
- Remote-cluster lifecycle and compatibility-pinned runtime artifacts.
- Release automation and published OCI verification.
- Disposable end-to-end installation fixtures.

## Local validation

```bash
./scripts/tests/install-command-contract.sh
./scripts/minikube-up.sh
./scripts/minikube-verify.sh
./scripts/minikube-down.sh
```

Run published-artifact and remote-cluster scenarios only against disposable or
approved test environments.

## Security

Do not commit kubeconfigs, registry credentials, cloud keys, bootstrap tokens,
or production values. Release credentials belong in CI secrets.
