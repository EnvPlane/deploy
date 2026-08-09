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
helm upgrade --install envpilot oci://ghcr.io/envpilot/envpilot \
  --version <immutable-umbrella-version> \
  --namespace envpilot --create-namespace --values values.yaml --wait
```

The management chart must expose a stable private or public HTTPS endpoint that target Pods can reach. It must not be `localhost`, a port-forward address, `host.minikube.internal`, `envpilot.local`, or foreign Kubernetes Service DNS. Service DNS is valid only for same-cluster components.

The management values only enable the reconciler and grant it access to the
explicit Secret namespace; they contain no target endpoint, kubeconfig, token,
or remote release setting:

```yaml
global:
  envpilot:
    remoteClusterReconciler: {enabled: true}
envpilot-control-plane:
  rbac:
    remoteClusterCredentials: {enabled: true, namespaces: [envpilot]}
    remoteClusterReconciler: {enabled: true}
```

## Create a remote target

Create the project record first without a remote `cluster_id`, using the same ID that will be used for the RemoteCluster. This gives the reconciler a scoped Agent/Runner identity without a circular readiness dependency. Then create the RemoteCluster from **Settings → Remote clusters**.

Provide the remote Kubernetes API HTTPS endpoint, an existing management-cluster kubeconfig Secret reference or a one-time credential submission, the target-Pod-reachable control-plane HTTPS endpoint and optional CA Secret, bounded discovery/feature namespaces, and managed release names/namespaces.

The reconciler validates access, installs only canonical Agent/Runner charts from the active signed umbrella compatibility manifest, waits for their pod-context endpoint preflight and fresh authenticated heartbeats, then marks the target `healthy`. Only then can a project select it and run Bootstrap.

Use **Retry** for transient failures, **Rotate managed identity** after a stale bootstrap identity, and **Repair** after endpoint/RBAC correction. These are audited API actions; they do not reveal or reuse raw bootstrap tokens.

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
ENVPILOT_E2E_MANAGEMENT_CONTEXT=management \
ENVPILOT_E2E_TARGET_CONTEXT=target \
ENVPILOT_E2E_UMBRELLA_REF=oci://ghcr.io/envpilot/envpilot \
ENVPILOT_E2E_UMBRELLA_VERSION=<immutable-version> \
ENVPILOT_E2E_VALUES_FILE=values.yaml \
ENVPILOT_E2E_API_URL=https://api.envpilot.platform.internal \
ENVPILOT_E2E_UI_URL=https://ui.envpilot.platform.internal \
ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL=https://api.envpilot.platform.internal \
ENVPILOT_E2E_REMOTE_CONTROL_PLANE_TLS_SERVER_NAME=api.envpilot.platform.internal \
ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_FILE=/secure/path/current-ca.pem \
ENVPILOT_E2E_REMOTE_CONTROL_PLANE_ROTATED_CA_FILE=/secure/path/rotated-ca.pem \
ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT=https://kubernetes.target.internal \
ENVPILOT_E2E_REMOTE_CREDENTIAL_FILE=/secure/path/target-kubeconfig \
ENVPILOT_E2E_HELM_CHART_REF=oci://registry.example.test/charts/e2e \
ENVPILOT_E2E_APP_REPOSITORY_URL=https://git.example.test/acme/app.git \
ENVPILOT_E2E_GITOPS_REPOSITORY_URL=https://git.example.test/acme/gitops.git \
ENVPILOT_E2E_SCM_TOKEN_FILE=/secure/path/scm-token \
./scripts/published-remote-cluster-two-cluster-e2e.sh
```

CI may create disposable clusters for this harness, but neither the chart nor
the product creates clusters or private-network infrastructure.
