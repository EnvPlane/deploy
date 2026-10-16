# Minikube Flux and Traefik reconciler follow-up, 2026-10-13

Decision: **LOCAL PLATFORM READY; APPLICATION NOT INSTALLED.** Flux controllers
were installed on the isolated `envplane` profile. The Traefik provider change
is implemented and tested in source; its published reconciler image and chart
pin remain a separate release step (ZSM-015).

## Flux installation

- Target: Kubernetes `v1.35.9`, context `envplane`, dedicated kubeconfig under
  `.cache/zero-setup-minikube/runtime/kubeconfig`.
- Flux CLI and installed distribution: `v2.9.6`.
- Method: direct `flux install --version v2.9.6`, without Git bootstrap.
- Exported install manifest SHA-256:
  `e0b32861e2701c26336b1a25e5d2896d9f1bc0eed68c2115e2a80277a93cdf03`.
- `flux check` passed: source-controller `v1.9.6`, kustomize-controller
  `v1.9.6`, helm-controller `v1.6.5`, and notification-controller `v1.9.4`
  each have one ready replica. Eleven Flux CRDs and the standard three
  namespace NetworkPolicies are present.
- `bootstrapped: false`; there are no GitRepository, Kustomization or
  HelmRelease resources. Flux is not reconciling the application or existing
  platform Helm releases.

All 18 platform/system Pods were `1/1 Running` with zero restarts at final
readback. The node remained Ready with `3800m` CPU and `5632Mi` memory
allocatable, and `kubectl top nodes` returned metrics. Helm still listed only
the existing Traefik and cert-manager releases; the `envplane` application
namespace remained absent.

## ZSM-006 implementation

The reconciler now registers Traefik's
`traefik.io/ingress-controller` and the exact chart `41.7.1` package checksum.
Existing-provider detection checks the named IngressClass, namespace, Service
and Deployment labels/selectors, available Deployment replica, and a ready
EndpointSlice or legacy Endpoints address. A mismatched or orphaned named
class fails closed. The optional live read-only Go test detected the actual
`traefik/traefik` installation. Managed chart URL, version and package checksum
are checked independently per provider. The Helm contract routes managed
Traefik through the regular Job with operator-supplied installation RBAC;
legacy nginx retains its separate installer. No release is adopted or swapped.

Validation: `go test ./...`, the seven-profile umbrella Helm/kubeconform
matrix, Traefik/legacy hook and schema negative contracts, the read-only live
Traefik detection, pinned Actions contract and image-publication contract all
passed. Additional local bugs found and fixed during testing have tickets
ZSM-012 through ZSM-014 and ZSM-016 through ZSM-018. ZSM-015 tracks publishing
and pinning the new image before this provider can be used from a published
application chart.

The local single-node host-path platform still does not prove production HA,
CSI snapshot or durable storage, trusted public TLS, or first-run application
acceptance. [Platform setup](../../platform/minikube/README.md) contains the
version lock and reproduction commands.
