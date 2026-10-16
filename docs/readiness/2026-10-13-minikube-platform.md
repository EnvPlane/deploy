# Local Minikube platform verification, 2026-10-13

Decision: **LOCAL PLATFORM READY; APPLICATION NOT INSTALLED.** The user
authorized this management cluster and its platform controllers after the
earlier preparation-only pass. No envplane umbrella release or application
namespace was created. Production application readiness remains a separate gate.

Source configuration: [platform/minikube](../../platform/minikube/README.md).
Machine-readable live evidence: [platform report](2026-10-13-minikube-platform.json).
Flux was installed later the same day; see the
[Flux and Traefik follow-up](2026-10-13-flux-traefik-followup.md).
The earlier signed `0.4.731` candidate lock remains unchanged.

## Installed target

- Profile/context: `envplane`; node: `envplane`, Ready, Kubernetes `v1.35.9`.
- Driver/runtime: Docker / containerd `2.3.4`; CNI: Calico.
- Docker node container: enforced 4 CPU and 6 GiB memory.
- Scheduler budget after the local driver correction: `3800m` CPU and `5632Mi`
  memory allocatable. The remaining container budget is reserved for node services.
- CoreDNS, default `standard` Minikube host-path provisioner, metrics-server
  `v0.9.0`, Calico node and kube-controllers are healthy.
- Gateway API standard `v1.6.3` CRDs installed from the SHA256-checked bundle.
- Traefik chart `41.7.1`, proxy `v3.7.14`, Helm revision 2, deployed.
- cert-manager `v1.21.2`, Helm revision 1, deployed; controller, webhook and
  CA injector Ready. Gateway API integration is enabled.
- Default IngressClass/GatewayClass: `traefik`; Gateway:
  `traefik/local-platform`, Accepted and Programmed.
- Traefik Service: NodePort, `31080` HTTP / `31443` HTTPS. No LoadBalancer,
  public endpoint, host-port reservation or persistent tunnel was created.
- All 14 remaining platform/system Pods Ready at the final readback.

Kubeconfig is local and ignored by Git:
`.cache/zero-setup-minikube/runtime/kubeconfig` in the deploy checkout, mode 0600.
Use it explicitly as documented in the platform README. The global kubeconfig
still has no selected context. `bethunder-local`, the orphaned policy candidate
configuration and existing issuer test containers were not modified.

## Functional checks

The checks ran in an explicitly owned temporary namespace with a digest-pinned
BusyBox image. They passed once after controller installation and again after
the kubelet scheduler-budget correction.

| Check | Result / evidence |
| --- | --- |
| Service DNS | Cluster service FQDN resolved; HTTP response reached the backend |
| Pod networking baseline | Both client Pods reached the backend before policy installation |
| Calico enforcement | Explicitly allowed client still succeeded; denied client failed after NetworkPolicy applied |
| Ingress | Traefik routed the test host to the actual backend |
| Gateway API | Gateway Programmed; HTTPRoute Accepted/ResolvedRefs; actual host-based HTTP response succeeded |
| Dynamic storage | Default-class PVC Bound; written content survived writer Pod deletion and replacement reader Pod |
| cert-manager | Temporary namespaced self-signed Certificate reached Ready, revision 1; private key was never read |
| Metrics | `kubectl top nodes` returned fresh resource usage |
| Installer preflight | Corrected exact RBAC, default storage, API and anonymous OCI pull checks passed without warnings |
| Cleanup | Owned smoke namespace deleted; its PVC/PV absent in final API readback |
| Application absence | Helm contains only Traefik and cert-manager releases; no envplane namespace/workloads |

The self-signed certificate is a local controller issuance test, not a trusted
production certificate. Smoke cleanup proves API resource removal; it does not
certify physical secure erasure or management-plane DR. These probes are not
project-bound Agent/Runner readiness evidence for an uninstalled application.

## Fixes and follow-ups

- ZSM-007 fixed the Traefik chart-41 values contract: `service.spec.type`
  controls Service type. The first pod was healthy but Helm waited for an
  unintended LoadBalancer. This task-owned Service was corrected, then Helm
  revision 2 persisted the reviewed NodePort profile. No external LB provider
  was installed to mask the error.
- ZSM-008 fixed over-advertised scheduler capacity: the node reported the
  entire 12-CPU/11.67-GiB Docker VM while its container has smaller limits.
  The helper derives local reservations, preserves the original kubelet file,
  restarts only this kubelet and verifies the intended Ready/allocatable state.
  Resource-unit normalization (ZSM-009) prevents `5632Mi` being mistaken for a
  mismatch with the equivalent `5767168Ki`.
- ZSM-010 fixed installer RBAC parsing and scope, StorageClass LIST permission,
  strict pin/name validation and inherited registry credentials. Negative
  permission regressions and live readback passed. The diagnostic creates no
  Kubernetes resources and reads no Secret objects.
- ZSM-006 remains open: register a maintained ingress provider in the optional
  application platform reconciler. Its nginx-only registry is not required for
  the zero-values path or external Ingress/Gateway use. ingress-nginx retirement
  is verified in the [official announcement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

Every issue has a Codex implementation prompt in the dated project issue folder
under `~/Downloads/issues/`. Source changes are committed separately by iteration
and pushed together for review; the preflight edit triggers release publication
on main, so this change uses a review branch rather than an automatic release.

## Next boundary

The cluster can host the reviewed zero-setup application installation after
that installation is authorized. Keep its first-run owner/tenant membership,
fresh authenticated Agent/Runner, scoped copy approvals, priced FinOps, stable
trusted TLS/SCM endpoint, provider production gates and full DR acceptance open.
Local host-path storage and a single node do not establish CSI snapshots or HA.
