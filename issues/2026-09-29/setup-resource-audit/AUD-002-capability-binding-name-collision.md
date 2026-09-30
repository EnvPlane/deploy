# AUD-002: Two fixed capability bindings render with the same Kubernetes identity

Status: fixed locally in the envplane-agent child chart; CI and release verification pending.
Priority: P1
Estimated effort: S

## Evidence

deploy/deploy/helm/envplane-agent/templates/rbac.yaml:101-120

Helm render for release remote-agent and cluster customer-west with both fixed roles produces two ClusterRoleBindings named remote-agent-envplane-agent-envplane-remote-cluster-customer-we with different immutable roleRef values. Raw truncation removes the distinguishing suffix.

## Implementation prompt for Codex

Use deterministic hash suffixes covering full role identity, release and namespace. Add YAML-object identity uniqueness checks for short and maximum-length names, plus an upgrade test.

Implement in the relevant child repositories. Preserve existing installations and tenant isolation. Commit each verified iteration with English messages. Report local, CI and live results separately.
