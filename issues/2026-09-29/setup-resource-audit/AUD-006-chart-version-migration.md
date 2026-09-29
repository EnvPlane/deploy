# AUD-006: Fixed-role code requires coordinated chart publication and migration

Status: confirmed by source audit; not fixed.
Priority: P1
Estimated effort: M

## Evidence

deploy/deploy/helm/envplane-agent/Chart.yaml:5; deploy/deploy/helm/envplane/Chart.yaml:16-18; deploy/.github/workflows/publish-agent-chart.yaml:29; control-plane/internal/server/remote_cluster_reconciler.go:1068

Agent source changed while chart version remains 0.2.29. Control plane unconditionally sends existingClusterRoles, which older published charts ignore. Existing target profiles lack newly required roles. This makes a push insufficient to establish a working upgrade.

## Implementation prompt for Codex

Publish a new immutable child chart version, update all pins/vendored packages and compatibility capability gating. Supply an idempotent migration of the target profile and ownership-safe retirement of old chart roles. Test old install -> new release and rollback. Verify actual published contents before marking complete.

Implement in the relevant child repositories. Preserve existing installations and tenant isolation. Commit each verified iteration with English messages. Report local, CI and live results separately.
