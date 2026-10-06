# Include project binding identities in the standard installer profile

Status: implemented locally; contract tests passed, not applied to live clusters.

The standard renderer now accepts repeatable `--project-id`, derives identities
through the existing exact-binding renderer and records deduplicated names on
the installer ClusterRole. The full reviewed profile continues to support unknown
future project IDs without additional operator patches. Review metadata does not
restrict authorization. Document the cluster-wide metadata GET permission and
admission-bounded writes; do not add workload or Secret access in baseline scopes.

Codex prompt: preserve identity parity with actual Helm templates, custom runtime
namespaces and arbitrary project IDs; test invalid IDs, duplicates and unchanged
admission policies. Never auto-apply this privileged profile during UI tests.
