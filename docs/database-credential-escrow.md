# Generated database credential escrow (opt-in)

Agent chart source `0.2.39` can project an existing encryption-key Secret and an
existing reviewed binding Secret into the Agent runtime. It does not provision
keys, escrow namespace, permissions, imports, database accounts or data. No default
installation receives extra Secret access. Main installer/approval integration is
still required before this can be enabled for normal project onboarding.

```yaml
agent:
  databaseCredentialEscrow:
    enabled: true
    namespace: <separately-protected-escrow-namespace>
    keyRef: <durable-operator-key-version-id>
    keySecret: <existing-operator-key-secret>
    keySecretKey: key
    bindingsSecret: <existing-reviewed-binding-secret>
    bindingsSecretKey: bindings.json
```

This is a reviewed configuration shape, not an executable installation command.
Place the two projected Secrets in the Agent Pod namespace, restrict their custody
to the operator and mount them read-only. The key entry is exactly 32 raw bytes,
not a password/passphrase or its textual base64 representation. Do not print it,
put it in chart values/Git or reuse a placeholder. The keyRef is a metadata-only
version reference and must remain available with the exact key for old escrow.
The separate escrow namespace must not be a disposable feature namespace. Back up
its immutable encrypted Secrets and the key separately under protected retention;
neither namespace/PVC cleanup nor cluster replacement automatically migrates them.

`bindings.json` is an array of reviewed authorizations, with no credential bytes:

```json
[
  {
    "binding": {
      "clusterId": "<actual-cluster-id>",
      "tenantId": "<tenant>",
      "projectId": "<project>",
      "environmentId": "<environment>",
      "itemId": "<immutable-plan-item>",
      "generator": "mysql-password-v1:DB_PASSWORD",
      "namespace": "<exact-feature-namespace>",
      "secretName": "<exact-target-secret>",
      "pvcs": [
        {"namespace": "<exact-feature-namespace>", "name": "<claim>", "uid": "<observed-UID>", "volumeName": "<observed-volume>"}
      ]
    },
    "initializeAuthorized": false
  }
]
```

All referenced claims must already be Bound and match exact UID/volume identity.
Only authorize initialization for reviewed empty data, never merely because an
application Secret is missing. UID-changing restores require separately reviewed
identity mapping/re-encryption; no automatic assumption about copied data occurs.
A metadata-only one-time marker prevents reuse of stale initialization permission
after escrow loss. Concurrent source/restore changes must be frozen by the normal
coordinator; metadata preconditions are not a distributed multi-object transaction.

## Required narrowly scoped administration

- Named GET of each exact PVC and metadata PATCH of those claims only. UID and
  resourceVersion JSON Patch preconditions are mandatory. No PVC data/volume writes
  or node/exec privilege is introduced by this flow.
- GET of exact named encrypted escrow objects, plus Secret CREATE in the dedicated
  escrow namespace. CREATE cannot be name-restricted by Kubernetes RBAC: isolate
  that namespace; do not put keys or plaintext import credentials there. No escrow
  update/delete/list/watch is needed.
- If importing, GET of the one exact operator input Secret in the target namespace.
- The key/binding projections do **not** require Agent API GET/list/watch of keys.
  Do not grant broad Secret read/write to make a mount work.

The chart deliberately renders no automatic additional escrow/key Role. Main must
calculate exact ciphertext object names from the canonical binding and obtain the
normal administrator-reviewed installer profile. Agent/runtime enrollment still
uses normal authentication; this path is not an authorization bypass.

## Metadata-only installer profile computation

Agent exports `BuildDatabaseCredentialEscrowAccessProfile` with typed
`DatabaseCredentialEscrowAccessProfileInput`. Pass reviewed authorizations, exact
escrow/ServiceAccount references, nonempty metadata `KeyRef`, protected projected
key/binding Secret names and `NamespaceSecretCreateReviewed: true`. That boolean
acknowledges the CREATE limitation for review; it does not apply permissions or
establish a live grant. No key file or credential values enter the helper.

The standalone local command emits review-only Kubernetes Role/RoleBinding List
JSON. Run from the Agent source checkout, with actual reviewed metadata substituted:

```sh
go run ./cmd/db-credential-recovery-profile \
  --reviewed-bindings /absolute/private/path/reviewed-bindings.json \
  --escrow-namespace <dedicated-ciphertext-namespace> \
  --service-account-namespace <actual-agent-pod-namespace> \
  --service-account <exact-runtime-service-account> \
  --key-ref <metadata-only-key-version-id> \
  --protected-secret <agent-pod-namespace>/<existing-key-secret> \
  --protected-secret <agent-pod-namespace>/<existing-binding-secret> \
  --acknowledge-namespace-secret-create
```

This template is not a ready-to-run command and has **no apply step**. KeyRef is
not a Secret name and is not emitted into RBAC. The command reads only a regular,
reviewed binding file (maximum 1 MiB), rejecting plaintext-key/password fields,
unknown/duplicate/case-duplicate fields and trailing JSON. Invalid inputs produce
no stdout and sanitized errors. Output contains only metadata/names and rules,
never keys, plaintext credential values or password hashes.

Profile generation rejects mixed cluster/tenant/project scopes and conflicting
target namespace environment identities. Escrow namespace must differ from every
target namespace and ServiceAccount Pod namespace. Target namespaces themselves
must also differ from the ServiceAccount Pod namespace: this profile is for isolated
feature recovery and cannot add Secret GET in the projected key/binding trust domain.
Protected key/binding references
cannot become imports. Per-namespace PVC/import permissions are sorted and exact,
and escrow GET names use the same canonical locator as recovery. No ClusterRole,
wildcards, Secret list/watch/update/delete, key API reads or target Secret CRUD are
added. Existing normal materialization permissions remain a separate profile.

An administrator still must confirm the escrow namespace is actually dedicated
and ciphertext-only, check generated Role names against existing foreign objects
and review delegated rights before applying through the normal workflow. Offline
metadata validation cannot prove those infrastructure facts. Kubernetes CREATE
cannot be name-limited; PVC PATCH cannot be metadata-field-limited by RBAC. Apply
appropriate admission/broker restrictions where needed. Named RBAC is not a UID
lock or ownership proof: runtime UID/resourceVersion verification remains required.
The default Helm escrow flag still creates **no automatic RBAC**.

Pass the actual projected key/binding references and any other known protected
Secret references, even though the array is optional. The Pod-namespace prohibition
holds even when references are omitted. Protection for keys/bindings located outside
that trust domain is only provable for explicitly supplied references; the offline
helper does not discover unknown key locations. Do not use this isolated-feature
profile for recovery in the Agent Pod namespace or claim it verifies key custody.

## Missing Secret and escrow: operator recovery boundary

1. Preserve/freeze the exact DB/PVC; do not delete data or reset initialization
   markers. Check normal account authentication using a verified operator backup.
2. If the credential is known and verified, supply it as an existing Opaque Secret
   in that exact target namespace, with application and engine password aliases
   equal. Keep plaintext out of shell arguments, logs, tickets and Git.
3. Review the exact binding and authorize `importAuthorized: true` with
   `importCredentialSecretName: <exact-existing-input-secret>`. Leave
   `initializeAuthorized: false` for retained data. Give only named GET to that
   input; never use a cross-tenant reference.
4. Retry through normal authenticated materialization. Agent commits/read-backs
   AEAD escrow, marks/rechecks PVC identity and atomically creates the missing target
   Secret. It leaves the input and encrypted escrow intact. Verify normal DB login
   and application readiness; then revoke import permission and handle the input
   Secret under the operator's reviewed retention workflow.
5. If no verified backup exists, **the password cannot be derived** here. Use a
   separately approved, engine-specific administrative rotation procedure, verify
   it, then import the known result. No automated SQL/root/pod-exec recovery exists.

Missing key, unreadable/tampered escrow, PVC drift or failed durable readback stops
recovery without target Secret writes. Cleanup requires both no namespace PVCs and
authenticated escrow matching the existing credential; missing key cannot delete
the last credential. Target deletion also requires matching Secret UID and
resourceVersion, so concurrent replacement fails instead of deleting the new Secret.
Agent never deletes encrypted escrow. Key/escrow disaster
recovery and production KMS custody remain separate responsibilities.

Implementation uses Go [AEAD authenticated additional data](https://pkg.go.dev/crypto/cipher#AEAD)
and Kubernetes [immutable Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#immutable-secrets).
These facilities do not establish your production backups, key custody or approval
process. Tests are local crypto/HTTP/chart regressions, not live recovery evidence.
