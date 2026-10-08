# Scoped migration helper review and local regression acceptance

Status: locally reviewed/hardened; no infrastructure apply, source changes or push.

Reviewed flux-restricted-policy-bridge.py, reconcile-restored-mysql-credential.py
and scoped-config-snapshot.py, plus restored DB/cold-copy tickets.

Corrections: Flux child target namespaced exactly flux-system, UID/resourceVersion
and suspend preconditions, arbitrary patch/selector rejection and idempotent local
same-namespace rule; no deny-all mutation. MySQL strict restore boolean/alias guard,
ownership marker and precise mount validation, rollout-before-cleanup and Secret
delete UID/resourceVersion preconditions. Snapshot exports only fully scoped SA
cluster bindings, not mixed/unapproved subjects or implicit Flux scopes; validates
every restore object before any apply, rejects active workloads/source SA tokens,
and derives PVC component labels from real workload mounts rather than claim names.

All tests mock kubectl/age and do not contact clusters. Existing __pycache and
unrelated work are preserved. Review does not re-run parent live migration.
Parent reports final generation4 CNI proof passed, app2/feature ingress HTTP200,
eleven cold-copy hashes verified and source scaled0/PVCs retained.

## Codex implementation prompt / remaining limitations

Keep generic database credential lifecycle as a separate ticket: durable credential
generation, preserve-PVC/account rotation, supported-engine auth protocols and
recreate/restore tests. The temporary init-file helper is candidate fixture recovery
only; no skip-grant-tables, root credential extraction or data deletion. Root/child
Flux patches are not an atomic multi-object transaction; leave them suspended and
review a partial conflict rather than force unrelated fields. Failed MySQL prepare
or cleanup rollout may retain the owned temporary Secret; audit and recover using
its exact UID instead of broad deletion. Do not treat mocked tests as proof of
current live credential correctness or future complete generic lifecycle support.
