# AUD-007: Repeated namespaces render duplicate resources

Status: confirmed by source audit and local rendering; not fixed.
Priority: P2
Estimated effort: S

## Evidence

deploy/scripts/render-remote-cluster-rbac-profile.sh:51-60

Executing renderer with --managed-namespace base-api twice yields duplicate Role and RoleBinding identities. The array/newline membership test does not deduplicate.

## Implementation prompt for Codex

Replace membership check with portable deterministic set logic; validate missing argument values, canonical naming lengths and duplicate runtime namespace. Test parsed Kubernetes identity uniqueness.

Implement in the relevant child repositories. Preserve existing installations and tenant isolation. Commit each verified iteration with English messages. Report local, CI and live results separately.
