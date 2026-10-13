# Local management cluster controllers

This platform is installed independently of the envplane umbrella. The user
authorized cluster creation and platform controller installation on 2026-10-13;
application installation remains deferred. The frozen application candidate
is still `0.4.731`.

The platform lock is [controllers.lock.json](controllers.lock.json). The target
is profile/context `envplane`, Kubernetes `v1.35.9`, Docker driver, containerd,
Calico, 4 CPUs and 6144 MiB RAM. Use the dedicated kubeconfig and matching tools
from the deploy checkout:

```bash
export KUBECONFIG="$PWD/.cache/zero-setup-minikube/runtime/kubeconfig"
export PATH="$PWD/.cache/zero-setup-minikube/toolchain:/opt/homebrew/opt/kubernetes-cli@1.35/bin:$PATH"
kubectl --context envplane get nodes
```

## Ownership and capabilities

| Component | Owner / version | Purpose |
| --- | --- | --- |
| Calico | Minikube CNI | Pod routing and enforced NetworkPolicies |
| CoreDNS | Kubernetes baseline | In-cluster DNS |
| Storage provisioner | Minikube addon, `standard` default class | Dynamic single-node host-path PVCs |
| metrics-server | Minikube addon, `v0.9.0` | Kubernetes resource metrics |
| Gateway API CRDs | Platform, standard `v1.6.3` | GatewayClass/Gateway/HTTPRoute APIs |
| Traefik | Platform Helm release `traefik`, chart `41.7.1`, proxy `v3.7.14` | Ingress and Gateway API controller |
| cert-manager | Platform Helm release `cert-manager`, `v1.21.2` | Certificate controller, webhook and CA injector |
| FluxCD | Direct Flux CLI install `v2.9.6` in `flux-system` | Four GitOps controllers and CRDs; no source or sync configured yet |

Traefik owns the default IngressClass and GatewayClass `traefik`, and the
`traefik/local-platform` Gateway. Its service uses NodePorts `31080` (HTTP) and
`31443` (HTTPS). The dashboard and insecure API are disabled. No host ports or
public load balancer are allocated. With the Docker driver on macOS, use an
explicit loopback service port-forward for host access:

```bash
kubectl --context envplane -n traefik port-forward --address 127.0.0.1 svc/traefik 8080:80 8443:443
```

These ports expose the controller; application routes and a trusted application
certificate do not exist yet. cert-manager Gateway API support is enabled.
No public ACME account or DNS/cloud credentials are configured. CoreDNS handles
service discovery; external-dns is unnecessary for loopback local access.

Flux is installed without bootstrap. `flux check` reports all four controllers
Ready and `bootstrapped: false`; no GitRepository, Kustomization or HelmRelease
has been created for EnvPlane. The default application uses Helm Direct and
does not require Flux. The local host-path backend has no CSI snapshot
capability or production HA/durability guarantee. Install a real CSI backend
and its snapshot controller only when a concrete snapshot/provider scenario
is selected; adding snapshot CRDs alone would not provide that capability.

## Reproduce the platform

Before creating a profile, inventory existing Minikube profiles and Docker
capacity. Do not reuse an incompatible profile or alter `bethunder-local`.
The orphaned `bethunder-policy-candidate` configuration is a separate ticket.
The global kubeconfig/context is preserved.

```bash
mkdir -p "$(dirname "$KUBECONFIG")"
chmod 700 "$(dirname "$KUBECONFIG")"
minikube start -p envplane --driver=docker --container-runtime=containerd \
  --kubernetes-version=v1.35.9 --cni=calico --cpus=4 --memory=6144mb \
  --disk-size=30g --addons=default-storageclass,storage-provisioner,metrics-server \
  --keep-context --interactive=false
chmod 600 "$KUBECONFIG"
python3 scripts/configure-minikube-budget.py --kubeconfig "$KUBECONFIG" \
  --output .cache/zero-setup-minikube/kubelet-budget.json --apply
mkdir -p .cache/zero-setup-minikube/controllers
curl -fSL https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml \
  -o .cache/zero-setup-minikube/controllers/gateway-api-v1.6.3.yaml
```

Verify the downloaded manifest SHA256 against the lock before applying it:

```bash
python3 - <<'PY'
import hashlib, json
from pathlib import Path
lock = json.loads(Path('platform/minikube/controllers.lock.json').read_text())
manifest = Path('.cache/zero-setup-minikube/controllers/gateway-api-v1.6.3.yaml')
assert hashlib.sha256(manifest.read_bytes()).hexdigest() == lock['gatewayAPI']['sha256']
PY
kubectl --context envplane apply --server-side --field-manager=envplane-local-platform \
  -f .cache/zero-setup-minikube/controllers/gateway-api-v1.6.3.yaml
helm pull oci://ghcr.io/traefik/helm/traefik --version 41.7.1 \
  --destination .cache/zero-setup-minikube/controllers
helm pull oci://quay.io/jetstack/charts/cert-manager --version v1.21.2 \
  --destination .cache/zero-setup-minikube/controllers
```

Compare each printed OCI digest with its entry in the lock; stop on a mismatch.
Install only the pinned downloaded packages, with the reviewed platform values:

```bash
helm upgrade --install traefik .cache/zero-setup-minikube/controllers/traefik-41.7.1.tgz \
  --kube-context envplane --namespace traefik --create-namespace \
  -f platform/minikube/traefik-values.yaml --wait --timeout 5m
helm upgrade --install cert-manager .cache/zero-setup-minikube/controllers/cert-manager-v1.21.2.tgz \
  --kube-context envplane --namespace cert-manager --create-namespace \
  -f platform/minikube/cert-manager-values.yaml --wait --timeout 5m
flux check --pre --kubeconfig "$KUBECONFIG" --context envplane
flux install --version v2.9.6 --namespace flux-system --export \
  > .cache/zero-setup-minikube/controllers/flux-v2.9.6.yaml
python3 - <<'PY'
import hashlib, json
from pathlib import Path
lock = json.loads(Path('platform/minikube/controllers.lock.json').read_text())
manifest = Path('.cache/zero-setup-minikube/controllers/flux-v2.9.6.yaml')
assert hashlib.sha256(manifest.read_bytes()).hexdigest() == lock['flux']['manifestSha256']
PY
flux install --version v2.9.6 --namespace flux-system \
  --kubeconfig "$KUBECONFIG" --context envplane
flux check --kubeconfig "$KUBECONFIG" --context envplane
```

The Docker driver can advertise the entire Docker VM's capacity to Kubernetes
despite a smaller node-container cgroup limit. The budget helper computes
`systemReserved` from that difference plus 200m CPU and 512 MiB memory for the
node services. This installation therefore has **3800m CPU and 5632 MiB memory
allocatable to Pods**, inside the enforced 4 CPU / 6 GiB container envelope.
The node's `capacity` field still describes the VM; use `allocatable` for
scheduling and record the cgroup limits separately for capacity/FinOps review.
The helper refuses another target, unlimited containers or unmanaged kubelet
reservations; it preserves the original configuration inside this node at
`/var/lib/kubelet/config.yaml.before-envplane-budget` and restarts only its
kubelet. Reapply after changing Docker VM/profile resource limits or recreating
the profile, then verify Node Ready and controller health. This is a local
driver accommodation, not a change to the production application chart.

For a failed budget change, restore only this node's preserved configuration
and restart its kubelet; return the platform readiness decision to blocked
until the resource envelope and health are reverified.

Gateway API CRDs precede both controllers. Do not enable Minikube's ingress
addon alongside Traefik: the ingress-nginx project is retired, and a second
default IngressClass would make route ownership ambiguous. The platform
reconciler now recognizes an existing Traefik controller through explicit
`provider=traefik`, `namespace=traefik`, `existingClassName=traefik` settings.
Its chart changes remain on a draft review branch; the published application
chart still contains the older reconciler image. The existing Gateway path
works independently of this optional reconciler.

## Verification

Require healthy controller rollouts, fresh metrics, dynamically provisioned
PVC write/read across Pod recreation, service DNS, successful Ingress and
Gateway routing, and real allowed/denied traffic under Calico. A temporary
namespaced self-signed certificate can prove local cert-manager issuance;
it does not prove a publicly trusted application endpoint. Remove only the
owned smoke-test namespace after the checks, preserving the platform releases.

```bash
kubectl --context envplane -n kube-system rollout status daemonset/calico-node --timeout=5m
kubectl --context envplane -n kube-system rollout status deployment/calico-kube-controllers --timeout=5m
kubectl --context envplane -n kube-system rollout status deployment/metrics-server --timeout=5m
kubectl --context envplane -n traefik rollout status deployment/traefik --timeout=5m
kubectl --context envplane -n cert-manager rollout status deployment/cert-manager --timeout=5m
kubectl --context envplane -n cert-manager rollout status deployment/cert-manager-webhook --timeout=5m
kubectl --context envplane -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=5m
kubectl --context envplane -n flux-system rollout status deployment/source-controller --timeout=5m
kubectl --context envplane -n flux-system rollout status deployment/kustomize-controller --timeout=5m
kubectl --context envplane -n flux-system rollout status deployment/helm-controller --timeout=5m
kubectl --context envplane -n flux-system rollout status deployment/notification-controller --timeout=5m
flux check --kubeconfig "$KUBECONFIG" --context envplane
kubectl --context envplane top nodes
bash scripts/envplane-install-preflight.sh --version 0.4.731 \
  --namespace envplane --kube-context envplane --output /dev/null
helm --kube-context envplane list --all-namespaces
```

Read [the live verification report](../../docs/readiness/2026-10-13-minikube-platform.md)
and [the Flux follow-up](../../docs/readiness/2026-10-13-flux-traefik-followup.md)
before application installation. Cluster readiness is separate from the
application's production gates and does not authorize its deployment.

Sources: [Traefik Helm chart](https://github.com/traefik/traefik-helm-chart),
[cert-manager OCI installation](https://cert-manager.io/docs/installation/helm/),
[cert-manager Gateway configuration](https://cert-manager.io/docs/usage/gateway/),
[ingress-nginx retirement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/),
and [Flux installation](https://fluxcd.io/flux/installation/).
