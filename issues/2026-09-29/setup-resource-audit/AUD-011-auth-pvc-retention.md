# AUD-011: Auth PVC preservation is documented but absent from chart lifecycle

Status: confirmed by source audit; not implemented.
Priority: P1
Estimated effort: M

## Evidence

control-plane/internal/server/remote_cluster_reconciler.go:380-383,1009-1031; deploy/deploy/helm/envplane-agent/templates/auth-pvc.yaml:1-24; deploy/deploy/helm/envplane-runner/templates/auth-pvc.yaml:1-24

Remote removal promises to preserve auth PVCs, but Helm uninstall receives ordinary chart-owned claims with no retention annotation. Source-level lifecycle mismatch; destructive live removal was not run.

## Implementation prompt for Codex

Define explicit retain/recover/purge semantics for auth claims. Implement ownership-aware retention and later cleanup without leaking orphaned claims forever. Validate managed claim, existing external claim, recovery and purge behavior.

Commit verified iterations with English messages. Report local tests and live verification separately.
