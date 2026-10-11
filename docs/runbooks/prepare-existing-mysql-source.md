# Prepare an existing MySQL source

This is a privileged operator tool, not an ordinary copy worker or a completed
UI/controller onboarding integration. No current application database has been
changed by developing/testing it.

## Prerequisites and safety

- Official MySQL 8.0/8.4, one-replica StatefulSet, default entrypoint, explicit
  Bound datadir PVC and same-namespace Service. Other layouts fail closed.
- MYSQL_ROOT_PASSWORD already references a working administrator Secret. An
  unknown random root password cannot be recovered by changing an env variable.
- Explicit administrator Kubernetes access to source metadata, the exact source
  Pod exec, dedicated Secret creation/read and the exact StatefulSet patch.
  Secret CREATE cannot be resource-name limited by Kubernetes RBAC; do not
  silently give that namespace-wide right to a copy worker.
- Approved short source restart, reviewed rollback/source backup and a plan
  to persist the resulting TLS reference in the real Helm/GitOps desired state.
- Python 3, kubectl and OpenSSL. Root and backup credentials never go in flags,
  printed previews or a compiled project. The review JSON contains references
  and fingerprints only; store it with operator-only access nevertheless.

## Preview and apply

Use explicit kubeconfig/context/namespace, never the ambient kubectl context:

```sh
python3 scripts/prepare-mysql-source.py preview \
  --kubeconfig /operator/protected/kubeconfig --context reviewed-target \
  --namespace source-namespace --statefulset source-mysql \
  --pvc source-data --service source-mysql --tenant tenant-id --project project-id
```

Save the metadata-only JSON into an operator-owned reviewed file. Review exact
source identities, desired-state ownership, TLS hostname, restart and grants.
Only then approve the displayed digest:

```sh
python3 scripts/prepare-mysql-source.py apply \
  --kubeconfig /operator/protected/kubeconfig --context reviewed-target \
  --namespace source-namespace --plan /operator/protected/reviewed-plan.json \
  --approve-plan REVIEWED_DIGEST --allow-source-restart
```

Helm-owned sources additionally require `--allow-reconciled-workload-change`.
This is an explicit acknowledgement, NOT automatic synchronization of GitOps.
For test-app chart 0.1.4, retain complete existing values and persist the returned
TLS Secret name as `mysql.tls.existingSecretName` before another reconciliation.
Never switch to partial values or assume the tool updated the Git repository.

Successful output contains only backup Secret/user/key and public CA Secret/key /
TLS hostname references. Rescan through authenticated discovery, save these in
the normal MySQL source policy and complete its separate approval/fence checks.
Do not substitute an administrative preparation result for copy evidence.

## Effects and verification

- Existing application/root credentials and source PVC bindings stay unchanged.
- Creates a separate immutable backup Secret, source-only server TLS Secret and
  public-only CA Secret. CA signing private key is temporary, not exported.
- Adds TLS mounts/config only, with source UID/resourceVersion tests; performs a
  normal source rollout. Client TLS verification is never disabled; backup user
  requires SSL without globally breaking non-TLS application clients.
- Creates a separate backup user: schema SELECT/SHOW VIEW/TRIGGER/EVENT and
  global SHOW_ROUTINE/BACKUP_ADMIN. These catalog privileges are not purely
  read-only SQL privileges; routine execution remains bounded by the copy worker.
  No ALL, GRANT OPTION, global SELECT, application-password rotation or data
  deletion. Exact account/schema/grants are checked before verified status.
- Verifies a real TLS session and acquisition/release of LOCK INSTANCE FOR BACKUP.
  This is preparation proof, not a complete data-copy/schema compatibility proof.

## Failure, retry and lifecycle

Retain the reviewed plan and owned Secrets; retry uses the same credential and
cannot adopt another account or silently repair a partial SQL grant. UID/spec
drift, missing objects, expired TLS or a failed rollout stop verification. Restore
requires a separately reviewed administrator action; no automatic PVC deletion
or rollback occurs. Client password tmp files use umask 077 and an EXIT trap;
an abnormal Pod termination can require operator inspection of its ephemeral
filesystem. Temporary file removal is not forensic secure erase.

Generated server certificates expire after 90 days; CA after 365 days. Dedicated
renewal/rotation must be implemented/reviewed before production use. Normal
copy verification must reject expired TLS, never weaken it.

## Fresh test-app base

For a **new empty** base installation, chart 0.1.4 supports
`mysql.auth.persistAdminCredential=true`. It generates an immutable separate
root Secret and retains the owned value on subsequent Helm reads. It refuses
generation when mysql-data already exists or in a feature environment. For a
DBA-provided existing credential use `mysql.auth.adminSecretName` and
`mysql.auth.adminPasswordKey`; the chart neither reads nor adopts that Secret.
These settings do not reset the password of an existing database.

## Verification performed

- 14 unit/mocked operation cases: deterministic preview, authority/configuration
  drift, injection/layout refusal, exact grants, approval-before-write, collisions,
  retry and retained Secrets after patch failure.
- Disposable networkless official MySQL 8.0: TLS SAN validation, exact grants,
  required SSL, lock/unlock, original row preservation and tmp-file cleanup.
- 6 test-app Helm rendering cases and helm lint.
- Read-only preview against current test-app-base refused its missing retained
  administrator Secret. No source SQL, restart, Secret write or grant occurred.

This does not certify product/UI or target-cluster Kubernetes live preparation.
