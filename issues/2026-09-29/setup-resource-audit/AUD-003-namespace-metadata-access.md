# AUD-003: Project Agent loses access to Namespace metadata

Status: confirmed by source audit; not fixed.
Priority: P1
Estimated effort: M

## Evidence

control-plane/internal/server/remote_cluster_reconciler.go:1056-1069; agent/agent/kubernetes.go:477-516; deploy/scripts/render-remote-cluster-rbac-profile.sh:118-140

Project Agent receives only fixed capability reader (IngressClass/CRD/StorageClass). It receives neither namespace list nor exact namespace get. Agent's explicit namespace path requests GET /api/v1/namespaces/{name}; namespaced Roles cannot authorize a Namespace object. New setup will receive Forbidden.

## Implementation prompt for Codex

Design explicit namespace metadata authorization consistent with bounded scope, or redesign inventory reporting with equivalent ownership metadata. Test actual API resource attributes and Agent discovery; do not merely assert rendered values.

Implement in the relevant child repositories. Preserve existing installations and tenant isolation. Commit each verified iteration with English messages. Report local, CI and live results separately.
