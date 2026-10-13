# Published zero-setup candidate on local Minikube

Prepared on 2026-10-13. **PLATFORM READY, APPLICATION NOT DEPLOYED.** The user
subsequently authorized cluster creation and platform controller installation.
Read [the live platform report](../readiness/2026-10-13-minikube-platform.md)
and [controller configuration](../../platform/minikube/README.md) for the
current state. Full production readiness remains NO-GO until the installed
application acceptance gates pass.

## Frozen candidate

- Umbrella: `oci://ghcr.io/envplane/envplane`, version `0.4.731`.
- OCI digest: `sha256:92c7b029e7a85ec03d26dcd50618ec15301039cf8351357a9cb05e30f16b68f5`.
- Deploy source: `4bd953a8cc3af05b3dc93bcaf72762f80d1f8daa`.
- [Preparation evidence](../readiness/2026-10-13-minikube-zero-setup/report.json),
  signed index and compatibility manifest are retained beside the report.
- Profile/context: `envplane`; release/namespace: `envplane`.
- Kubernetes: `v1.35.9`; Minikube: `v1.39.0`; Docker driver; containerd;
  Calico; 4 CPUs, 6144 MiB memory, 30 GiB requested disk.
- Helm baseline: `v3.21.3`, matching the release workflow. A checksum-checked
  local binary is staged under `.cache/zero-setup-minikube/toolchain/helm3`.
  The same artifact preparation also passed on host Helm `v4.3.0`; this does
  not establish installed Helm 4 upgrade or rollback behavior.
- Matching kubectl: `/opt/homebrew/opt/kubernetes-cli@1.35/bin/kubectl`
  (`v1.35.9`). The default host kubectl is `v1.37.1` and must not be used
  against the selected 1.35 cluster.

The `envplane` profile now exists and is Ready with its platform controllers.
Existing `bethunder-local`, the orphaned
`bethunder-policy-candidate` configuration and running issuer test containers
are outside this installation. The initial preparation pass created no cluster;
the subsequent authorized platform pass created only `envplane`. The global
kubeconfig currently has no selected context; use the dedicated kubeconfig.
Future dry-runs use an isolated `MINIKUBE_HOME` as shown below.

Use the published umbrella with no values, manual registration Secrets or
local image builds. `scripts/minikube-up.sh` builds local source images and
installs the control-plane child chart; it is a development fixture and is
not the entry point for this acceptance pass.

## Repeat preparation without deployment

Run from the deploy repository. Downloading release assets writes local files
only. The preparation check runs signature verification, anonymous OCI chart
pulls, lint/template, registry image descriptor inspection and exact component
CI verification. It does not call Kubernetes, start Minikube, install Helm
releases, pull image layers into Docker or persist rendered Secrets.

```bash
mkdir -p .cache/zero-setup-minikube/0.4.731
gh release download envplane-v0.4.731 --repo envplane/deploy \
  --pattern '*.json' --pattern '*.tgz' \
  --dir .cache/zero-setup-minikube/0.4.731 --skip-existing
python3 scripts/prepare-minikube-zero-setup.py \
  --release-dir .cache/zero-setup-minikube/0.4.731 \
  --output-dir .cache/zero-setup-minikube/prepared-731-repeat \
  --helm .cache/zero-setup-minikube/toolchain/helm3
```

Use a fresh output directory for each pass; an existing report is never silently
reused. On other machines select the installed Helm binary with `--helm` and
the Docker Buildx plugin executable with `--buildx`. Dependencies are Python 3,
Helm, Cosign, Docker Buildx and authenticated GitHub Actions read access through
`gh`. Registry checks use temporary empty credential configurations.

The local Helm baseline can be restaged without modifying global Homebrew:

```bash
mkdir -p .cache/zero-setup-minikube/toolchain
cd .cache/zero-setup-minikube/toolchain
curl -fSL https://get.helm.sh/helm-v3.21.3-darwin-arm64.tar.gz -o helm-v3.21.3-darwin-arm64.tar.gz
curl -fSL https://get.helm.sh/helm-v3.21.3-darwin-arm64.tar.gz.sha256sum -o helm-v3.21.3-darwin-arm64.tar.gz.sha256sum
shasum -a 256 -c helm-v3.21.3-darwin-arm64.tar.gz.sha256sum
tar -xzf helm-v3.21.3-darwin-arm64.tar.gz darwin-arm64/helm
cp darwin-arm64/helm helm3
chmod 755 helm3
ln -sf helm3 helm
cd ../../..
```

The platform dry-run also passed for this exact cluster configuration. It
validates configuration and does not prove actual boot, capacity, storage,
pod networking or NetworkPolicy enforcement:

```bash
MINIKUBE_HOME="$PWD/.cache/zero-setup-minikube/dryrun-home" \
minikube start --dry-run -p envplane --driver=docker \
  --container-runtime=containerd --kubernetes-version=v1.35.9 \
  --cni=calico --cpus=4 --memory=6144mb --disk-size=30g \
  --addons=default-storageclass,storage-provisioner,metrics-server \
  --keep-context --interactive=false
```

## Application execution after deployment is authorized

Cluster creation and platform preflight below have been executed under the
subsequent authorization. They are retained as reproduction instructions.
**The application install in step 5 has not been executed or authorized.**

1. Repeat the candidate check. Review the existing `envplane` profile with
   `minikube profile list -o json`. Inventory errors for existing profiles must
   remain visible. Never infer profile absence from an inventory failure or
   reuse an existing profile without reviewing its workloads and CNI. The
   prepared target contains platform controllers and no application release.
2. Recheck `docker info`, `docker stats --no-stream` and free host/Docker disk
   space. The observed Docker budget was 12 CPUs and 11.67 GiB RAM; existing
   containers used approximately 4.14 GiB. The planned 6 GiB cluster plus a
   1 GiB reserve fits that observed memory usage, but growth can remove this
   headroom. Disk availability and actual cluster scheduling remain pending.
   If insufficient, resize Docker through the operator or obtain authorization
   to stop specific test containers. Do not restart Docker or delete profiles
   as an implicit resource fix.
3. Select the staged tools and a dedicated local kubeconfig, then create only
   the selected management profile:

```bash
export PATH="$PWD/.cache/zero-setup-minikube/toolchain:/opt/homebrew/opt/kubernetes-cli@1.35/bin:$PATH"
export KUBECONFIG="$PWD/.cache/zero-setup-minikube/runtime/kubeconfig"
mkdir -p "$(dirname "$KUBECONFIG")"
chmod 700 "$(dirname "$KUBECONFIG")"
minikube start -p envplane --driver=docker \
  --container-runtime=containerd --kubernetes-version=v1.35.9 \
  --cni=calico --cpus=4 --memory=6144mb --disk-size=30g \
  --addons=default-storageclass,storage-provisioner,metrics-server \
  --keep-context --interactive=false
chmod 600 "$KUBECONFIG"
python3 scripts/configure-minikube-budget.py --kubeconfig "$KUBECONFIG" \
  --output .cache/zero-setup-minikube/kubelet-budget.json --apply
```

4. Inspect the new profile explicitly and run the existing preflight. Redirect
   the optional StorageClass override to `/dev/null` so this acceptance still
   installs with zero values:

```bash
kubectl --context envplane get nodes
kubectl --context envplane get storageclass
kubectl --context envplane -n kube-system get pods
bash scripts/envplane-install-preflight.sh \
  --version 0.4.731 --namespace envplane --kube-context envplane --output /dev/null
helm --kube-context envplane list --all-namespaces
```

Require Ready nodes, one usable default StorageClass, healthy Calico/CoreDNS,
metrics-server, required Helm RBAC and no existing release in the selected
namespace. Stop if the target or state differs from the reviewed plan.

5. Install the frozen production chart. This is the single application install
   command; the extra flags bind it to the reviewed cluster and bound the wait:

```bash
helm upgrade --install envplane oci://ghcr.io/envplane/envplane \
  --version 0.4.731 --kube-context envplane \
  --namespace envplane --create-namespace --wait --timeout 10m
kubectl --context envplane -n envplane rollout status deployment/envplane-control-plane --timeout=10m
kubectl --context envplane -n envplane rollout status deployment/envplane-frontend --timeout=10m
kubectl --context envplane -n envplane get pods,pvc,svc
kubectl --context envplane -n envplane port-forward --address 127.0.0.1 svc/envplane-frontend 3000:3000
```

Open `http://127.0.0.1:3000`. Port 3000 was free during preparation; check again
before forwarding. Loopback access avoids the earlier `envplane.local:80`
listener conflict. Public TLS/SCM/remote-cluster endpoints have separate
acceptance requirements. No ingress add-on or hosts-file change is needed for
local first-run.

## Installed acceptance and decision

Record exact chart digest, deployed image IDs, test times and receipts for each
gate. A Running pod or an existing Kind report does not complete a fresh pass.

| Gate | Required result | Current evidence |
| --- | --- | --- |
| Clean install | Zero values, generated credential retention, healthy data services and persistent claims | Platform Ready; application install pending |
| First run | Real provider setup, initial owner, active default-tenant membership, logout/login | Pending |
| Authorization | Owner/admin/developer/viewer paths; ordinary 403 retains tenant; privileged controls match membership | Source fix ancestry and component CI checked; installed matrix pending |
| Project onboarding | UI-created project; authenticated fresh Agent/Runner heartbeat and discovery; reconciliation completes | Source fixes included; installed gate pending |
| CNI | Fresh allow/deny traffic proof for the current project/cluster | Platform allow/deny probe passed; future project-bound proof pending |
| Lifecycle | Create, update, recreate and delete via the normal project Runner | Pending |
| DB/PVC | Independent approval of the current review; scoped copies, retained data, denied out-of-scope access | Pending |
| FinOps | Nonempty priced telemetry, ownership reconciliation, warning/deny budget scenarios | Pending |
| SCM and remote | Stable endpoint, actual signed delivery, MR replay/close cleanup, remote isolation | Pending external endpoint and fixtures |
| Payments/issuer | Approved provider mode, real evidence and production gates from payment documentation | Separate gate; free first-run does not require paid activation |
| Reliability/DR | Upgrade preserves credentials/PVCs; complete management-plane restore and audit backlog acceptance | Pending |
| Supply chain | Independent SBOM/provenance acceptance and supported capacity/topology | Index signature and immutable artifacts verified; broader acceptance pending |

Existing fixes are included: control-plane `c21d875` is an ancestor of the
candidate API source, frontend `fb7e6e7` and `a648fb8` are ancestors of its UI
source, and Agent `f045767` is an ancestor of its Agent source. These checks do
not substitute for browser membership and authenticated executor acceptance.

Single-node Minikube with host-path storage validates this local install path;
it does not establish HA, durable production storage, multi-node/multi-zone
failure handling or production availability guarantees. Calico is selected
because NetworkPolicy enforcement requires a capable CNI; the default vanilla
Minikube network does not supply that proof. See the official
[Minikube Network Policy guide](https://minikube.sigs.k8s.io/docs/handbook/network_policy/)
and [start flags](https://minikube.sigs.k8s.io/docs/commands/start/).

## Failure and recovery

If install or acceptance fails, retain the profile, Helm history and PVCs for
diagnosis; collect metadata/events and sanitized logs. Create a ticket, fix and
commit each locally fixable bug, and rerun its affected checks. Do not switch
to a local image to mark the published candidate successful. A new fix needs a
new published candidate and a fresh verified lock before installed retesting.

For an upgrade regression, review `helm --kube-context envplane -n envplane
history envplane` and migration compatibility before a rollback. A first install
has no prior release revision; do not claim rollback exists. No namespace/profile
deletion or database rollback is part of the current authorization.

Follow-up tickets with implementation prompts are in the project-named folder
under `~/Downloads/issues/`, dated `2026-10-13/zero-setup-minikube/`, separated
into release, platform and acceptance directions.
