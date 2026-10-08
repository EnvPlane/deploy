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

Generic credential lifecycle remains OPEN; this fixture repair is not its fix.

## Codex implementation prompt

Prevent generated Secret rotation while preserving existing database PVCs unless
the database account is reconciled through an explicitly approved engine-specific
rotation protocol. Bind credential generation to durable environment/database
state, not Pod restarts or physical namespace UID alone. Keep encrypted references,
no raw passwords in records/logs/Git. Add create/recreate/preserve-PVC/restore
regressions across supported engines. Never silently weaken auth or discard data
to make a readiness probe pass. This scoped migration recovery is not a proof of
the entire generic database credential lifecycle implementation.
