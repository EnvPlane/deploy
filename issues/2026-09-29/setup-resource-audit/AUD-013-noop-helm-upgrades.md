# AUD-013: Unchanged executor reconciliation can create redundant Helm revisions

Status: confirmed by source audit; not implemented.
Priority: P2
Estimated effort: M

## Evidence

control-plane/internal/server/same_cluster_project_reconciler.go:366-384,964; control-plane/internal/server/remote_cluster_reconciler.go:780-819

Same-cluster startup reconciliation enters apply for existing projects. Shared apply locates chart and upgrades existing release without semantic desired-state equality check. This means unnecessary OCI work, revisions, API writes and waits; it does not prove every pass restarts Pods. Remote projects already have an outer signature gate.

## Implementation prompt for Codex

Add per-component canonical desired-state comparison including chart/image identity and safe values, before unnecessary chart resolution where possible. Keep health/drift repair, explicit credential recovery and namespace/capability expansion effective. Test stable second reconcile produces no upgrade and real drift still repairs.

Commit verified iterations with English messages. Report local tests and live verification separately.
