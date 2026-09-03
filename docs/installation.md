# Install envplane

This is the supported default path for an already provisioned Kubernetes
cluster. It installs one immutable OCI umbrella release and does not require
registration, a Secret, a values file, or manual child-chart assembly.

## 1. Check prerequisites

- Kubernetes 1.26 or newer.
- Helm 3.14 or newer.
- Permission to create the `envplane` namespace and chart resources.
- A default StorageClass for bundled PostgreSQL and Redis persistence.
- Anonymous outbound access to the public `ghcr.io` chart and images.

The chart does **not** provision a cluster or automatically install an Ingress
controller, Gateway API implementation, DNS controller, certificate manager,
metrics server, CSI driver, or cloud integration. Supply those capabilities
before enabling a feature that depends on them.

Optional non-mutating preflight:

```bash
scripts/envplane-install-preflight.sh --version <stable-version> --namespace envplane
```

The preflight reads no Secret data and creates no cluster resources.

## 2. Install the stable release

<!-- envplane:canonical-install-command:start -->
```bash
helm upgrade --install envplane oci://ghcr.io/envplane/envplane --version 0.4.167 --namespace envplane --create-namespace --wait
```
<!-- envplane:canonical-install-command:end -->

<!-- envplane:stable-release-links:start -->
Stable release: `0.4.167` · [versioned installation guide](https://github.com/envplane/deploy/blob/8b28b618c378a49d435bcf1b5550d40f5d670d63/docs/installation.md) · [guided installer](https://envplane-install.alexandr928857.chatgpt.site/install)
<!-- envplane:stable-release-links:end -->

The selected version and command are generated from the same signed stable
release index consumed by the guided installer. `latest` is not a supported
version selector.

## 3. Verify and complete first-run

```bash
kubectl -n envplane rollout status deployment/envplane-control-plane --timeout=10m
kubectl -n envplane rollout status deployment/envplane-frontend --timeout=10m
kubectl -n envplane port-forward svc/envplane-frontend 3000:3000
```

Open <http://127.0.0.1:3000>. The initial authentication screen guides the first
owner through local setup or a supported identity provider. Provider client
secrets are entered only in the authenticated, write-only setup flow; they do
not belong in Helm values, shell history, or this website.

After authentication, create a project and run Bootstrap. The same-cluster
Agent and Runner are already part of the umbrella; do not install their child
charts manually. Remote clusters are added later through **Settings → Remote
clusters**.

## Free limits and activation

A new installation uses the built-in free plan without checkout or license
activation:

| Resource | Free limit |
|---|---:|
| Projects | 3 |
| Managed remote clusters | 1 |
| Active environments | 2 |
| Members | 3 |
| Environment TTL | 72 hours |
| Audit retention | 7 days |

The running API remains the authority for effective entitlements. Owners and
admins can review usage and start hosted activation under **Settings → Plan and
billing**. Card data never enters envplane. On-prem installations can instead
use the tenant-bound offline-license flow supplied by their administrator.
Installing or upgrading the chart never silently changes the active plan.

## Upgrade

Read the target release's versioned guide and back up retained database/PVC
data. Keep non-secret operator choices in one values file, then use the wrapper,
which resets chart defaults before applying the signed compatibility manifest
and its immutable artifact set:

```bash
scripts/upgrade-umbrella.sh \
  --release envplane \
  --chart oci://ghcr.io/envplane/envplane \
  --version <new-stable-version> \
  --namespace envplane \
  --operator-values values.yaml
```

The wrapper always passes `--reset-values`. Do not replace it with
`--reuse-values`; that can retain stale nested image selections. If no operator
values are needed, use an empty, non-secret YAML document (`{}`).

For rollback:

```bash
helm history envplane --namespace envplane
helm rollback envplane <known-good-revision> --namespace envplane --wait --timeout 15m
```

## Uninstall

```bash
helm uninstall envplane --namespace envplane --wait
```

This removes Helm-owned workloads. Retained PVCs, external services,
operator-managed Secrets, and platform add-ons are deliberately not deleted.
Back up and remove retained data separately when required.

## Troubleshooting

| Symptom | Check | Resolution |
|---|---|---|
| `helm pull` or install cannot reach GHCR | `helm pull oci://ghcr.io/envplane/envplane --version <stable-version>` | Restore public OCI egress, or follow the private-mirror procedure in the advanced guide. |
| Pods are Pending with an unbound PVC | `kubectl get storageclass` and `kubectl -n envplane get pvc` | Configure a default StorageClass or select an existing class in operator values. The chart does not install a CSI driver. |
| Helm reports `forbidden` | Run `scripts/envplane-install-preflight.sh --version <stable-version> --namespace envplane` | Grant only the RBAC verbs reported by preflight, then retry the same command. |
| Frontend is not reachable | Check both rollout commands and `kubectl -n envplane get svc envplane-frontend` | Keep the port-forward running for local first-run, or configure an existing Ingress/Gateway implementation. |
| First-run has already been claimed | Inspect the initial-authentication status in the UI/API | Sign in with the configured provider; use the authenticated recovery flow instead of rerunning initial setup. |
| Upgrade keeps old images | `helm get values envplane -n envplane` | Remove image overrides and rerun the wrapper without `--reuse-values`. |
| External database connection fails | Check pod events and Secret metadata, never Secret values | Verify the existing Secret name/key, network policy, TLS trust, and database reachability. |

For production topology and non-default choices, continue with
[advanced installation](installation-advanced.md). For API-managed remote
targets, see [remote clusters](remote-clusters.md).
