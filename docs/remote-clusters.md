# API-managed remote clusters

EnvPlane installs core services once in the management cluster. A remote cluster is added through **Settings → Remote clusters** or `/api/v1/remote-clusters`; it is never encoded in umbrella values and an operator never installs Agent or Runner charts manually.

```text
operator/UI or API
       |
       v
management-cluster EnvPlane API ── Remote Cluster Reconciler ── Kubernetes API
       |                                      |                       |
       |                                      | Helm Go SDK           v
       |                                      +--------------> managed Agent + Runner
       |                                                          | HTTPS preflight/heartbeat
       +<---------------------------------------------------------+
```

## Install the management cluster

The application installation is exactly one command against an already provisioned Kubernetes cluster. Enable the Remote Cluster Reconciler in the values file; remote targets themselves do not belong in it.

```sh
helm upgrade --install envplane oci://ghcr.io/envplane/envplane \
  --version <immutable-umbrella-version> \
  --namespace envplane --create-namespace --values values.yaml --wait
```

The management chart must expose a stable private or public HTTPS endpoint that target Pods can reach. It must not be `localhost`, a port-forward address, `host.minikube.internal`, `envplane.local`, or foreign Kubernetes Service DNS. Service DNS is valid only for same-cluster components.

The management values only enable the reconciler and grant it access to the
explicit Secret namespace; they contain no target endpoint, kubeconfig, token,
or remote release setting:

```yaml
global:
  envplane:
    remoteClusterReconciler: {enabled: true}
envplane-control-plane:
  rbac:
    remoteClusterCredentials: {enabled: true, namespaces: [envplane]}
    remoteClusterReconciler: {enabled: true}
```

## Create a remote target

Create the project record first without a remote `cluster_id`, using the same ID that will be used for the RemoteCluster. This gives the reconciler a scoped Agent/Runner identity without a circular readiness dependency. Then create the RemoteCluster from **Settings → Remote clusters**.

Provide the remote Kubernetes API HTTPS endpoint, an existing management-cluster kubeconfig Secret reference or a one-time credential submission, the target-Pod-reachable control-plane HTTPS endpoint and optional CA Secret, bounded discovery/feature namespaces, and managed release names/namespaces.

The reconciler validates access, installs only canonical Agent/Runner charts from the active signed umbrella compatibility manifest, waits for their pod-context endpoint preflight and fresh authenticated heartbeats, then marks the target `healthy`. Only then can a project select it and run Bootstrap.

Use **Retry** for transient failures, **Rotate managed identity** after a stale bootstrap identity, and **Repair** after endpoint/RBAC correction. These are audited API actions; they do not reveal or reuse raw bootstrap tokens.

### Prepare target RBAC once

Before saving a Remote Cluster, render and review the fixed target profile. It
uses the chosen cluster ID only in resource names; it does not depend on a
project ID, a Helm release name, a token, or a kubeconfig. Add every existing
namespace that the target Agent/Runner must manage or discover. The
reconciler updates the fixed namespace-metadata reader with each validated
project namespace, so future project-owned namespaces remain bounded to the
current discovery set without granting namespace list/watch access.

```sh
./scripts/render-remote-cluster-rbac-profile.sh \
  --cluster-id customer-west \
  --runtime-namespace envplane-system \
  --managed-namespace base-api \
  --managed-namespace base-web > customer-west-envplane-rbac.yaml
kubectl --context customer-west apply -f customer-west-envplane-rbac.yaml
```

Create the target kubeconfig for the generated ServiceAccount according to the
cluster's normal authentication policy, store it in the management-cluster
Secret requested by the UI, and then save the Remote Cluster. The profile gives
`--managed-namespace` only read-only discovery access; it does not grant
Secrets or write verbs there. Runtime mutation permissions remain in the
runtime namespace, while feature-writer access is bound only by the reconciler
into verified project-owned namespaces. Add `--flux-namespace NAME` only when
read-only Flux status is explicitly needed. The profile has
no workload permission outside the namespaces explicitly passed above. It
pre-installs fixed read-only capability roles and bounded project parent roles;
the reconciler may bind those parent roles only after it has created and
verified a project-owned namespace. This removes the former requirement to
grant `clusterroles/create` or `clusterroles/escalate` for every generated
Agent release.

### Dynamic feature Kustomization status delegation

For Flux projects with future feature environments, an administrator may add
`--flux-status-reader-namespace flux-system` to the reviewed profile above.
This separate opt-in grants the installer only `get` on Kustomizations in that
namespace. It has no Secret, source, HelmRelease, list/watch, mutation, bind or
escalate permission. It supports arbitrary configured project and environment
names without a manual parent-role edit for every new feature.

Important: Kubernetes RBAC cannot restrict future names by prefix. The installer
can therefore read **any** Kustomization in the explicitly reviewed namespace;
this is not foreign-project read isolation for the installer. Project Agents
retain their computed exact-name status Roles; their scope is not widened.
Use a dedicated Flux namespace or keep explicit per-environment parent grants
if this metadata-read boundary is unacceptable. This flag does not grant the
separate source-writer access required for GitOps setup.

Existing credentials are never silently upgraded. Render, review and apply the
profile with administrator credentials, then retry project provisioning. The
control plane still checks exact required names before mutating Helm resources
and fails closed when the parent grant is missing. Do not combine the broader
`--flux-namespace` flag unless its additional discovery reads are also required.

### Project capability bindings are part of the initial access profile

Use the full profile above, not a credential restricted to the three cluster
runtime binding names. Initial connection preflight checks ClusterRoleBinding
`get/create/update/patch/delete` for projects created later. Before each project
Helm install, the server also derives its exact three Agent binding names from
the actual release, runtime namespace and fixed capability roles and checks
those names. A runtime-only credential is rejected before cluster installation;
preflight and Retry never grant permissions themselves.

Optionally add repeatable `--project-id orders --project-id payments` when
rendering the full profile. The installer ClusterRole annotation
`envplane.io/reviewed-project-bindings` lists the calculated chart identities for
operator review (deduplicated, no credentials). The annotation is informational,
not an authorization allowlist: the full profile supports arbitrary future IDs
without another per-project operator patch.

Kubernetes RBAC cannot match name prefixes. The full installer therefore can
read ClusterRoleBinding metadata cluster-wide; admission cannot restrict GET.
Writes remain constrained by the accompanying fail-closed admission policies,
fixed capability roles and Helm-owned runtime identities. No Secret/workload
access in baseline namespaces is added by this binding lifecycle permission.
An operator must review and install the complete profile and its admission
policies once. Already-connected targets using legacy exact-name profiles need
that one-time migration, then **Retry project executors**; a code update cannot
legitimately grant access that the target credential does not already possess.

## Project-owned namespaces

For a project targeting a connected cluster, open its **Bootstrap → Project-owned namespaces** panel and request a suffix. The server combines the remote target's configured allowed prefix, project ID, and suffix, checks the dedicated-namespace policy and limit, and queues reconciliation. A `202` response means *requested*, not created. The panel shows `ready` only after the target namespace and exact Agent/Runner access have reconciled and both runtimes have fresh heartbeats.

The target credential held by the management reconciler must be allowed to get/create Namespaces and install the project Agent/Runner Role and RoleBinding in the new namespace. Kubernetes RBAC cannot restrict `namespaces/create` by `resourceNames`; do **not** grant this cluster-wide verb to a project Runner. The management reconciler validates the requested name and refuses to adopt an existing namespace without matching project, target-cluster, and tenant ownership metadata. Project Agent/Runner permissions remain namespace-scoped after creation.

The generated profile also installs a `ValidatingAdmissionPolicy` for the
installer identity. It permits ClusterRoleBindings only for the fixed
read-only capability roles and Helm-managed Agent bindings; project workload
access must use the reconciler-created namespace RoleBindings. The policy also
blocks that installer identity from deleting or updating unrelated
ClusterRoleBindings. Keep this policy with the profile during upgrades.

Project-owned namespaces are not automatically deleted when the project record is removed, because the namespace may contain durable user workloads. Operators must review their contents and remove them explicitly. Environment namespaces keep their existing separate lifecycle.

## Upgrade, migration, and removal

Every reconciled component records an immutable compatibility-manifest hash and desired generation. Upgrades use exact OCI chart versions and image digests; Helm upgrades are atomic. An earlier signed umbrella compatibility set is the only rollback target.

Existing manual Agent/Runner releases are rejected by default. An operator must request **Migrate** explicitly after verifying identity and release ownership. Migration preserves the existing auth PVC name and imports no legacy endpoint, image, RBAC, or token values.

Deleting a remote target is controlled: the API returns `202`, the reconciler removes only releases and bootstrap Secrets labelled for that RemoteCluster, and it preserves auth PVCs and every shared platform dependency. A missing release is already-cleaned success; a foreign release stops removal with an actionable ownership error.

## Published two-cluster verification

`scripts/published-remote-cluster-two-cluster-e2e.sh` verifies published artifacts against two already provisioned contexts. It installs only the management umbrella, creates a project and RemoteCluster through the public API, and proves:

1. an API-managed private HTTPS endpoint profile, private-CA Secret reference, reconciler-managed CA distribution, and Agent/Runner init-container endpoint preflight in the target cluster;
2. fresh heartbeats, Bootstrap scan, Helm preflight and compile;
3. Full Environment create/delete through the browser UI, with its Helm release present only in the target cluster;
4. DNS endpoint loss, private-CA rotation, degraded diagnostics, and idempotent repair.

### Product contract versus private-network prerequisite

EnvPlane owns the RemoteCluster record, target Agent/Runner releases, scoped
trust Secret copy, target-pod probe, heartbeats, Bootstrap and Environment
lifecycle. It does **not** own network reachability outside Kubernetes. Before
running the published E2E, the platform operator must provide:

- two already provisioned Kubernetes contexts;
- a stable private or public HTTPS DNS name reachable from target Agent/Runner
  Pods, with DNS, routing/firewall and a serving certificate already in place;
- the current and rotated CA PEM files for that endpoint, plus a planned server
  certificate rotation which chains to the rotated CA;
- stable management API/UI URLs for the test client and a target Kubernetes API
  credential Secret/file with least-privilege RemoteCluster access.

The harness receives these as environment variables and stores CA/Kubernetes
material only in Kubernetes Secrets. It never creates clusters, tunnels,
port-forwards, DNS records, certificates or manual OCI child releases. A
`does-not-resolve.invalid` profile update is used only to prove DNS diagnostics;
the recovery path restores the API-managed profile and reconciles the existing
managed releases.

Example invocation (the exact endpoint and files are platform-owned):

```sh
ENVPLANE_E2E_MANAGEMENT_CONTEXT=management \
ENVPLANE_E2E_TARGET_CONTEXT=target \
ENVPLANE_E2E_UMBRELLA_REF=oci://ghcr.io/envplane/envplane \
ENVPLANE_E2E_UMBRELLA_VERSION=<immutable-version> \
ENVPLANE_E2E_VALUES_FILE=values.yaml \
ENVPLANE_E2E_API_URL=https://api.envplane.platform.internal \
ENVPLANE_E2E_UI_URL=https://ui.envplane.platform.internal \
ENVPLANE_E2E_REMOTE_CONTROL_PLANE_URL=https://api.envplane.platform.internal \
ENVPLANE_E2E_REMOTE_CONTROL_PLANE_TLS_SERVER_NAME=api.envplane.platform.internal \
ENVPLANE_E2E_REMOTE_CONTROL_PLANE_CA_FILE=/secure/path/current-ca.pem \
ENVPLANE_E2E_REMOTE_CONTROL_PLANE_ROTATED_CA_FILE=/secure/path/rotated-ca.pem \
ENVPLANE_E2E_REMOTE_KUBERNETES_ENDPOINT=https://kubernetes.target.internal \
ENVPLANE_E2E_REMOTE_CREDENTIAL_FILE=/secure/path/target-kubeconfig \
ENVPLANE_E2E_HELM_CHART_REF=oci://registry.example.test/charts/e2e \
ENVPLANE_E2E_APP_REPOSITORY_URL=https://git.example.test/acme/app.git \
ENVPLANE_E2E_GITOPS_REPOSITORY_URL=https://git.example.test/acme/gitops.git \
ENVPLANE_E2E_SCM_TOKEN_FILE=/secure/path/scm-token \
./scripts/published-remote-cluster-two-cluster-e2e.sh
```

CI may create disposable clusters for this harness, but neither the chart nor
the product creates clusters or private-network infrastructure.

### Reusable isolated Kind browser fixture

For the local two-Kind-cluster fixture only, run
`scripts/run-isolated-real-cluster-playwright.sh` instead of calling Playwright
directly. It checks the mounted private endpoint certificate before testing and
renews it when less than seven days remain. Renewal stages overlapping trust,
updates only the named test TLS/CA Secrets, restarts the endpoint and only the
target Deployments that mount the matching CA Secret, and then removes the old
trust anchor. It refuses non-Kind contexts. The browser storage-state file
must be fresh and private; the script never reads or prints its cookie values.

```sh
ENVPLANE_E2E_MANAGEMENT_CONTEXT=kind-envplane-e2e-management \
ENVPLANE_E2E_TARGET_CONTEXT=kind-envplane-e2e-remote \
ENVPLANE_E2E_REMOTE_CLUSTER_ID=e2e-remote-353 \
ENVPLANE_E2E_STORAGE_STATE=/private/tmp/current-e2e-storage-state.json \
ENVPLANE_E2E_BASE_URL=http://127.0.0.1:3000 \
ENVPLANE_E2E_API_URL=http://127.0.0.1:18080 \
./scripts/run-isolated-real-cluster-playwright.sh
```

Run `scripts/ensure-isolated-e2e-tls.sh check` with the three cluster variables
above for a read-only preflight. It reports certificate expiry and remaining
seconds, and fails when the endpoint identity, remaining lifetime, or exact
single-certificate trust copies do not match. `ensure` is the only mutating
mode. Override `ENVPLANE_E2E_TLS_MIN_VALID_SECONDS` and
`ENVPLANE_E2E_TLS_VALID_DAYS` only for isolated fixture tests. For other
platform-owned HTTPS endpoints, renew certificates through the platform's own
certificate manager instead.
