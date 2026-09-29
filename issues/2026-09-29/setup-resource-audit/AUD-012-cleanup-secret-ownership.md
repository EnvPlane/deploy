# AUD-012: Same-cluster project cleanup deletes bootstrap Secret by name only

Status: confirmed by source audit; not implemented.
Priority: P2
Estimated effort: S

## Evidence

control-plane/internal/server/same_cluster_project_reconciler.go:1088-1095

After release removal (including NotFound), deterministic bootstrap Secret is deleted with no ownership read or UID precondition. A replacement/foreign Secret using that name can be deleted.

## Implementation prompt for Codex

Read and verify project, manager and component metadata; delete with UID precondition. Preserve NotFound idempotency. Test foreign replacement, absent release and concurrent replacement.

Commit verified iterations with English messages. Report local tests and live verification separately.
