# AUD-001: Cluster-scoped binding can bypass intended namespace boundary

Status: confirmed by source audit; not fixed.
Priority: P1
Estimated effort: Security design + integration tests; L

## Evidence

deploy/scripts/render-remote-cluster-rbac-profile.sh:85-103; control-plane/internal/server/remote_project_reconciler.go:454-485

Installer can create ClusterRoleBindings and bind the feature-env-writer-parent ClusterRole. Those permissions compose into cluster-wide workload/Secret access; ownership checks in the API do not constrain direct use of the credential. It can also delete unrelated bindings. This contradicts the published isolation claim.

## Implementation prompt for Codex

Separate capability binding from namespaced delegation, and enforce binding scope with admission policy or a narrowly privileged target controller. Preserve dynamic project namespaces without namespace-wide/cluster-wide escape. Verify negative authorization against unrelated namespaces, cluster bindings and existing bindings.

Implement in the relevant child repositories. Preserve existing installations and tenant isolation. Commit each verified iteration with English messages. Report local, CI and live results separately.
