# AUD-004: Discovery namespace selection grants workload and Secret mutations

Status: fixed locally in the target RBAC profile; CI pending.
Priority: P1
Estimated effort: M

## Evidence

deploy/scripts/render-remote-cluster-rbac-profile.sh:15,53-60,227-285; deploy/docs/remote-clusters.md:64-86

--managed-namespace is documented for discover/manage but renders runtime-manager with create/update/delete for workloads, Secrets, PVCs, Services and Pods. Selecting an existing base app for scanning therefore expands write access unnecessarily.

## Implementation prompt for Codex

Split runtime, read-only discovery, feature writer and optional Flux scopes. Derive permission requirements from actual resource operations, and prove discovery-only namespaces deny writes and unnecessary Secret reads.

Implement in the relevant child repositories. Preserve existing installations and tenant isolation. Commit each verified iteration with English messages. Report local, CI and live results separately.
