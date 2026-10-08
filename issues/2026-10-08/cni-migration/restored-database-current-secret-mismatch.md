# Restored MySQL account differs from current generated Secret

Actual cold-copy matched all data/metadata digests. Base MySQL accepted its app
credential; feature MySQL rejected it. Current source Secret, restored target
Secret and target Pod environment all have identical SHA256, but the database
account has a different historical password. This exposes a pre-existing
Secret/database lifecycle mismatch, not evidence of corrupted data copying.

Explicit migration helper reconciles only the configured application account
inside the reviewed restored candidate through a temporary MySQL startup
init-file Secret. No skip-grant-tables, root credential extraction, role grants,
database/PVC deletion, source changes or plaintext host SQL. It requires the
verified cold-restore ledger, exact target namespace authorization and bounded
safe credential/username characters. Remove its init-file/configuration after
successful credential checks and verify another normal database restart.

Parent reports the scoped correction and clean restart complete, eleven original
cold-copy digests verified, application/MySQL Ready and candidate ingress HTTP200.
These are parent-verified live results, not this reviewer's repeated infrastructure
tests. Changing the database account intentionally changes mysql-data after the
initial cold-copy comparison; do not claim post-write bytes still match rollback.

Helper review added strict boolean restore evidence, source/target alias rejection,
reserved mount collision checks, StatefulSet UID/resourceVersion patch preconditions,
temporary Secret ownership tied to that StatefulSet UID, and cleanup that waits
for normal rollout then deletes only the exact Secret UID/resourceVersion. No live
operation was run during this review. Failed prepare/rollout can leave an owned
temporary Secret; do not auto-delete unrelated resources or force a rollback.
Historical temporary Secrets without the UID ownership label require manual review.

## Durable materializer prevention (local code, no live changes)

The Agent generated-secret executor previously called the random generator on
every execution and then applied those new bytes over an owned existing Secret.
Kubernetes SSA idempotency did not make random passwords idempotent. Runner and
bootstrap do not implement another random generator: bootstrap compiles typed
references/generator profiles; the Agent executes them on the target cluster.

Local prevention now reads/reuses the existing owned credential without a write.
A metadata-only identity digest binds tenant, project, environment, item, target
name and generator, independent of plan revision or namespace UID. Legacy Secrets
are reusable only with their exact original plan digest. No password/hash of a
password is persisted in command/status/Git; credential bytes remain in the target
Secret. Kubernetes encryption at rest is still an administrator prerequisite;
this change does not configure encryption or create a new escrow service.

All five supported DB profiles check application/engine aliases before reuse.
Creation uses atomic POST, so concurrent creators cannot overwrite a winner.
Missing credentials fail closed when any PVC exists in the target namespace;
unknown/denied inventory also fails closed. Cleanup refuses to delete generated
database Secrets until all namespace PVCs are removed. This deliberately includes
Pending claims and unrelated claims: no guessed claim-to-database association or
implicit permission widening. Existing installer PVC list/create Secret permissions
are required; no new permissions have been granted during this iteration.

Regression coverage includes create, restart/replay, recreate, restored Secret
with retained PVC, missing Secret with retained PVC, changed plan/foreign environment,
legacy records, alias mismatch, denied/malformed inventory and concurrent creation.
These are mocked unit/HTTP tests, not five live database engine restore tests.

### Remaining explicit constraints

- Existing historical DB-account/Secret mismatches cannot be detected from Secret
  aliases alone. No automatic account mutation, rotation or auth bypass was added.
- Restore must restore the approved encrypted credential **with** its data before
  provisioning. An orphan retained PV or data restored later is not discoverable
  through namespace PVC inventory. Concurrent external PVC restoration after the
  inventory check is not an atomic Kubernetes transaction; the restore coordinator
  must serialize restore and provisioning.
- Generic encrypted credential escrow, renamed-target restore mapping and approved
  engine-specific rotation workflows remain OPEN and require coordinated contract,
  lifecycle/approval and engine integration work. No plaintext credential reference
  or control-plane Secret payload was introduced as a shortcut.
- Revised-plan reuse intentionally leaves original cleanup ownership intact. A
  newer cleanup plan cannot silently adopt/delete the old Secret; review its original
  ownership or provide a separately approved ownership migration.
- Namespace-wide preservation can block unrelated DB initialization/cleanup. Future
  exact DB/PVC binding must come from an immutable reviewed lifecycle contract, not
  inference from names.

The fixture recovery and prevention are distinct. Do not mark the entire generic
credential/rotation/restore lifecycle closed on the strength of these local tests.

## Subsequent bounded escrow/recovery implementation

Local Agent code now provides authenticated AEAD escrow before target credential
writes, exact binding/PVC verification, one-time initialization markers, conditional
Secret cleanup and explicitly operator-authorized import from a named verified
credential backup. Agent chart source `0.2.39` exposes opt-in existing key/binding
Secret projections without default RBAC grants. See
`docs/database-credential-escrow.md` and Agent ticket
`issues/2026-10-08/database-lifecycle/lost-generated-database-credentials-encrypted-escrow.md`.

This narrows the prior OPEN escrow item to production/normal-onboarding integration:
protected key/escrow provisioning, exact approved fresh-PVC initialization order,
installer delegation, audit UI and UID-changing restore mapping are not completed
by enabling a chart flag. Existing accounts with unknown/no backup credentials
still need explicit engine-native administrative recovery. No live import, key,
Secret, PVC or account was created/changed during this code iteration.

## Codex implementation prompt

Prevent generated Secret rotation while preserving existing database PVCs unless
the database account is reconciled through an explicitly approved engine-specific
rotation protocol. Bind credential generation to durable environment/database
state, not Pod restarts or physical namespace UID alone. Keep encrypted references,
no raw passwords in records/logs/Git. Add create/recreate/preserve-PVC/restore
regressions across supported engines. Never silently weaken auth or discard data
to make a readiness probe pass. This scoped migration recovery is not a proof of
the entire generic database credential lifecycle implementation.
