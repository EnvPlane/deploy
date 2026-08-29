# EnvPlane installation

This is the supported production installation path for an already provisioned
Kubernetes cluster. EnvPlane is installed as one OCI umbrella release; it does
not provision a cluster or install a distribution-specific add-on.

## Prerequisites

The operator must provide:

- Kubernetes 1.26 or newer and Helm 3.14 or newer;
- a kubeconfig context with permission to create the release namespace and the
  explicitly enabled EnvPlane resources;
- a default StorageClass, or an explicitly configured storage dependency, when
  bundled PostgreSQL/Redis or persistence is enabled;
- an existing healthy Ingress controller, Gateway API implementation, DNS
  integration and/or storage provisioner when their mode is `existing`;
- anonymous image pulls for every enabled EnvPlane component; or, only when an
  operator deliberately selects a private mirror/workload, an existing registry
  Secret in each required namespace;
- existing Secret references for external PostgreSQL/Redis, optional registry pulls and
  provider credentials. Secret values are never placed in Git, values files or
  bootstrap sessions.

The target cluster, ingress/DNS provider and external database services are
owned by the platform team. For an internal PostgreSQL deployment, the chart
creates the database workload and a generated password Secret on first install
and preserves that Secret on upgrades. EnvPlane does not create tunnels,
minikube profiles or cloud infrastructure.

## Quick start

On a support-matrix cluster with a default StorageClass, the safe baseline is
one command and needs no values file or pre-created Secret:

<!-- envplane:canonical-install-command:start -->
```bash
helm upgrade --install envplane oci://ghcr.io/envplane/envplane \
  --version <published-umbrella-version> \
  --namespace envplane \
  --create-namespace \
  --wait
```
<!-- envplane:canonical-install-command:end -->

The chart installs API, frontend, internal PostgreSQL/Redis, same-cluster Agent
and Runner, retained PVCs, and a Helm-managed registration Secret. It creates no
Ingress, Gateway, DNS, StorageClass, tunnel or other cluster add-on. Use the
post-install port-forward printed in Helm NOTES for the first run. Create an
operator values file only to select a private registry, external data services,
an explicit StorageClass, or an existing Ingress/Gateway:

```yaml
envplane-control-plane:
  persistence:
    storageClassName: fast-ssd
```

`managed` retains chart-generated registration material across upgrades.
`existing` consumes an operator-created Secret named by
`global.envplane.firstStartRegistration.existingSecret`. Plaintext tokens must
never be put in values. Remote execution targets are configured after this
install through the authenticated UI/API RemoteCluster flow, not values or
manual child-chart commands. See [API-managed remote clusters](remote-clusters.md).

## Preflight and post-install handoff

Before installing, run the idempotent diagnostic helper. It checks Kubernetes
API access, the default StorageClass, the Helm caller's required RBAC, and an
anonymous pull of the selected immutable chart. It neither reads nor prints
Secret data, and it never creates cluster resources:

```sh
scripts/envplane-install-preflight.sh \
  --version <published-umbrella-version> \
  --namespace envplane \
  --output envplane-preflight-values.yaml
```

If it reports a missing StorageClass, ask the platform owner to configure one
or select a supported class in an operator values file. If it reports RBAC,
grant exactly the displayed permission to the Helm caller, then rerun. If the
anonymous pull fails, fix outbound registry access or choose a published version;
do not add a registry Secret for public EnvPlane artifacts.

The canonical command stays unchanged. If you deliberately generated an
explicit StorageClass override, add only this flag to it:

```sh
helm upgrade --install envplane oci://ghcr.io/envplane/envplane \
  --version <published-umbrella-version> \
  --namespace envplane --create-namespace --wait \
  --values envplane-preflight-values.yaml
```

After Helm reports success, use the same commands printed in NOTES:

```sh
kubectl -n envplane rollout status deployment/envplane-control-plane --timeout=10m
kubectl -n envplane rollout status deployment/envplane-frontend --timeout=10m
kubectl -n envplane port-forward svc/envplane-frontend 3000:3000
```

Open <http://127.0.0.1:3000> to start first-run onboarding.

## Helm Direct bootstrap default

The umbrella publishes and pins `envplane-e2e-workload` alongside its normal
child charts. New Draft bootstrap sessions receive its OCI ref and version in
Step 2, so a local/demo user can continue without typing a chart coordinate.
The dependency is disabled as an umbrella workload; only a project Runner
installs it.

To use an organization chart instead, override both public coordinates during
the Helm install or upgrade. These fields are not credentials and never grant
registry access:

```yaml
global:
  envplane:
    bootstrapDefaults:
      helmDirect:
        chartRef: oci://registry.example.com/platform/application
        chartVersion: "1.2.3"
```

An individual project can still replace the default before bootstrap compile.

## Same-cluster project executors and optional private registry access

When `global.envplane.sameClusterProjectExecutors.enabled` is true, project
Agent/Runner releases run in their dedicated executor namespace. Public
EnvPlane OCI charts and runtime images pull anonymously by default, so neither
the management nor executor namespace needs `envplane-ghcr`. Kubernetes image
pull Secrets are namespace-scoped only for an operator-selected private mirror
or private workload: materialize an identically named
`kubernetes.io/dockerconfigjson` Secret in the executor namespace. The chart
references only its name and the control plane verifies only Secret metadata,
never credential data, through the Kubernetes API.

For a local Minikube installation whose management registry Secret already
exists, run the repository script. The chart creates the executor namespace on
the first install; the script streams the registry Secret between `kubectl` processes,
does not print it, does not write it to disk, and refuses to force-overwrite a
target owned by another field manager:

```sh
./scripts/sync-namespaced-registry-secret.sh \
  --context bethunder-local \
  --source-namespace envplane \
  --target-namespace envplane-executors \
  --secret envplane-ghcr

helm upgrade --install envplane oci://ghcr.io/envplane/envplane \
  --version <published-umbrella-version> \
  --namespace envplane --create-namespace \
  --values operator-values/bethunder-local.yaml --wait
```

For production, prefer your external-secrets controller to materialize the
same registry credential in both namespaces from one secret-manager entry. If
an operator must create it from a protected local Docker config, use this
idempotent command in *each* namespace (the file must not be committed):

```sh
kubectl --context <production-context> --namespace envplane-executors \
  create secret generic envplane-ghcr \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson=/secure/path/ghcr-dockerconfig.json \
  --dry-run=client -o yaml | kubectl --context <production-context> apply -f -
```

Verify only metadata and type, never `.data`:

```sh
kubectl --context <context> -n envplane-executors get secret envplane-ghcr \
  -o jsonpath='{.type}{"\\n"}'
```

Keep the existing value references aligned with the target namespace:

```yaml
global:
  envplane:
    registry:
      existingSecret: envplane-ghcr # management namespace: Helm OCI client
    sameClusterProjectExecutors:
      enabled: true
      namespace: envplane-executors
      registry:
        existingSecret: envplane-ghcr
        imagePullSecret: envplane-ghcr # executor namespace: Agent/Runner Pods
```

## Remote-cluster management endpoint

Remote Agent and Runner pods must reach the management control plane through a
stable private or public HTTPS endpoint. The same-cluster Kubernetes Service DNS name is
never valid for a remote target. Configure only endpoint and Secret references
in the umbrella values; the chart does not create a tunnel, issue a certificate
or put certificate bytes in values:

```yaml
global:
  envplane:
    remoteControlPlane:
      endpoint: https://api.envplane.example.test
      tls:
        # Optional: required only when target pods do not trust the endpoint's
        # issuer through their system trust store.
        caSecretRef:
          name: envplane-remote-ca
          key: ca.crt
access:
  mode: ingress
  ingress:
    host: api.envplane.example.test
    className: nginx
    tls:
      enabled: true
      # Existing provider-managed server certificate Secret. EnvPlane never
      # reads or generates its contents.
      secretName: envplane-api-tls
```

For Gateway API or an external LoadBalancer, the platform owns server-certificate
attachment; configure its public HTTPS endpoint above. If `caSecretRef` is set,
the named CA Secret/key must already exist in the remote Agent and Runner
namespace. The Remote Clusters UI reads this safe endpoint metadata, pre-fills
the endpoint/CA reference and shows a prerequisite diagnostic when it is
missing or invalid. It rejects `envplane.local`, localhost,
`host.minikube.internal`, port-forwards and foreign `.svc` addresses.

## Platform dependency modes

Each of `platformDependencies.ingress`, `.dns` and `.storage` has one mode:

| Mode | Meaning |
|---|---|
| `disabled` | EnvPlane does not require or manage this capability. |
| `existing` | Reuse a healthy, compatible capability without adoption or mutation. |
| `auto` | Detect a healthy capability first; install only an explicitly configured provider when absent. |
| `managed` | Install/upgrade the explicitly selected pinned provider chart, with explicit ownership and cleanup policy. |

`auto` and `managed` require the platform dependency reconciler and pinned
provider configuration. They never guess cloud credentials. `existing` requires
the class/provider/Secret references appropriate to that capability. A degraded
or scope-mismatched capability blocks dependent features and is reported in the
reconciler status ConfigMap.

Provider credentials are supplied only as `credentials.existingSecret` (DNS) or
provider chart values that reference an existing Secret. The reconciler reads
metadata and health, never prints Secret data.

## Values examples

### Generic Kubernetes (ClusterIP, existing storage)

```yaml
access: {mode: disabled}
platformDependencies:
  ingress: {mode: disabled}
  dns: {mode: disabled}
  storage: {mode: existing, existingClassName: standard}
```

### nginx Ingress

```yaml
access:
  mode: ingress
  ingress: {host: envplane.example.test, className: nginx}
platformDependencies:
  ingress: {mode: existing, provider: nginx, existingClassName: nginx}
```

### AWS ALB

```yaml
access:
  mode: ingress
  ingress:
    host: envplane.example.test
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internal
platformDependencies:
  ingress: {mode: existing, provider: aws-alb, existingClassName: alb}
```

AWS credentials and the AWS Load Balancer Controller remain platform-owned.

### Gateway API

```yaml
access:
  mode: gateway
  gateway:
    name: shared-gateway
    namespace: gateway-system
    sectionName: https
    hostnames: [envplane.example.test]
```

### External PostgreSQL/Redis

```yaml
envplane-control-plane:
  postgres:
    mode: external
    external: {existingSecret: envplane-postgres-url, urlKey: database-url}
  redis:
    mode: external
    external: {existingSecret: envplane-redis-url, urlKey: redis-url}
```

### Private registry

```yaml
global:
  envplane:
    registry:
      mode: existing
      existingSecret: registry-credentials
```

This grants every enabled runtime workload pull access without changing the
release-selected images. Published umbrellas reject repository, tag or digest
overrides that conflict with their signed compatibility manifest. Mirror the
published immutable artifacts if required by your registry policy, then publish
a corresponding signed umbrella release; do not use `latest`.

## Upgrades, rollback and uninstall

Each published umbrella archive includes a signed compatibility manifest with
the exact immutable runtime image refs it selects. Do **not** use Helm
`--reuse-values` for umbrella upgrades: Helm would retain the old nested image
maps and silently keep the preceding release's digest.

Keep a durable operator values file (the same file used for installation) and
upgrade with the provided wrapper, which uses `--reset-values` and layers that
file over the new chart defaults:

```sh
scripts/upgrade-umbrella.sh \
  --release envplane \
  --chart oci://ghcr.io/envplane/envplane \
  --version <new-published-umbrella-version> \
  --namespace envplane \
  --operator-values values.yaml
```

This preserves operator configuration while applying the artifact pins signed
in the selected release. An explicit `envplane-*.image` or
`platformDependencyReconciler.image` override that conflicts with the selected
manifest is rejected before Helm mutates the release; update it to the selected
immutable ref or remove it from the operator file. Do not put credentials in
the values file or generated release metadata.

Helm owns the core release and its child resources; external detected
capabilities are never adopted or deleted. Managed providers are removed only
when their configured ownership and cleanup policy permit it. Back up
database/PVC data before rollback or uninstall.

For a failed published upgrade, inspect the release and restore a known-good
revision without changing values or deleting data:

```sh
helm status envplane --namespace envplane
helm history envplane --namespace envplane
helm rollback envplane <known-good-revision> --namespace envplane --wait --timeout 15m
```

To remove the product workloads, use the same release and namespace. This does
not delete retained PVC data, external dependencies or operator-managed Secrets:

```sh
helm uninstall envplane --namespace envplane --wait
```

The repository's `scripts/minikube-*.sh` and clean-install scripts are retained solely for
automated test fixtures. They are not required for, or part of, the production
installation path.
