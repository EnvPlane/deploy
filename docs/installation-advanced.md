# Advanced envplane installation

Start with the [default installation](installation.md). Use this guide only
when platform policy requires explicit production topology. Keep credentials in
an external secret manager or pre-created Kubernetes Secret; values files hold
references only.

## Production hardening

- Pin the exact stable chart version and retain its signed release index and
  compatibility evidence with the change record.
- Use a dedicated namespace, least-privilege Helm identity, NetworkPolicies,
  Pod Security admission, backups, and tested restore procedures.
- Provide a durable StorageClass or external data services before installation.
- Expose the API/UI only through a platform-owned Ingress or Gateway with TLS;
  the umbrella does not install an ingress controller, DNS controller,
  certificate manager, CSI driver, or cloud load-balancer integration.
- Configure remote-cluster access only through the authenticated API/UI. Do not
  copy bootstrap tokens or manually install Agent/Runner child charts.

The full dependency ownership contract is documented in
[platform dependencies](platform-dependency-contract.md).

## External PostgreSQL and Redis

Create connection Secrets in the release namespace using your secret manager,
then reference only their names and keys:

```yaml
envplane-control-plane:
  postgres:
    mode: external
    external:
      existingSecret: envplane-postgres-url
      urlKey: database-url
  redis:
    mode: external
    external:
      existingSecret: envplane-redis-url
      urlKey: redis-url
```

Disable or size bundled persistence according to the chart values for the
selected release. Validate database version, TLS trust, network policy,
connection limits, backup, and restore before cutover. Helm never owns or
deletes the external services or their Secrets.

## Private registry or mirror

Public release artifacts pull anonymously. If policy requires a private mirror,
mirror every immutable chart and image selected by the release compatibility
manifest. Do not retag mutable `latest` images or override one child artifact in
an otherwise signed release.

Materialize the pull Secret independently in every namespace that needs it and
reference its name:

```yaml
global:
  envplane:
    registry:
      mode: existing
      existingSecret: registry-credentials
    sameClusterProjectExecutors:
      enabled: true
      namespace: envplane-executors
      registry:
        existingSecret: registry-credentials
        imagePullSecret: registry-credentials
```

Never place `.dockerconfigjson`, passwords, or tokens in values or Git. Verify
only metadata and type:

```bash
kubectl -n envplane get secret registry-credentials -o jsonpath='{.type}{"\n"}'
kubectl -n envplane-executors get secret registry-credentials -o jsonpath='{.type}{"\n"}'
```

## Ingress, Gateway, DNS, and storage

Use `existing` mode to bind a platform-managed capability. `auto` and `managed`
modes require an explicitly selected, compatibility-pinned provider; they do
not guess providers or credentials. A missing provider is a configuration
error, not permission to install a cluster add-on.

```yaml
access:
  mode: ingress
  ingress:
    host: envplane.example.test
    className: nginx
    tls:
      enabled: true
      secretName: envplane-api-tls
platformDependencies:
  ingress:
    mode: existing
    provider: nginx
    existingClassName: nginx
  storage:
    mode: existing
    existingClassName: fast-ssd
```

For Gateway API, reference an existing Gateway. For remote clusters, configure
a stable HTTPS management endpoint and follow [remote clusters](remote-clusters.md).

## Operator values and lifecycle

Store one reviewed, non-secret operator values file. Use it for install,
upgrade, rollback planning, and disaster recovery. External capabilities remain
platform-owned and survive uninstall; chart-generated PVCs may be retained.
Review ownership before deleting any namespace or volume.
