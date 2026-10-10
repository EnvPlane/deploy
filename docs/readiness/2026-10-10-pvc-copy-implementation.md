# Offline PVC-copy implementation and release boundary

## Implemented locally

Identity-bound metadata-only contracts connect authoritative Agent PVC UID discovery to compiled API plans, leased Runner execution and server-derived UI availability. The first supported path is Flux/default-tenant offline filesystem copying, not Helm claim adoption or live database copying.

Runner creates only a new environment-owned destination claim, supports WaitForFirstConsumer binding, streams bounded data through Kubernetes exec and verifies content hashes plus file/directory/root UID, GID and mode. Durable receipts bind the plan and both PVC UIDs. A completed retry verifies existing content; partial/foreign targets are refused. No source credential or data dump is stored on the local host. Visible Linux ACL/xattr metadata is rejected rather than silently discarded; timestamps, sparse layout and filesystem flags are not a complete filesystem-clone guarantee.

Copy completion is a prerequisite, never an Environment Ready signal. API reserves the lifecycle/quota before allocating storage and checks compiled storage quota before ResourceQuota publication. Workloads publish only after the exact authenticated completion evidence. Public Bootstrap PATCH cannot supply source discovery, copy capability/results or runtime credential evidence.

Source helpers require a preinstalled, source-bound admission fence plus finite permissions. Policy status alone is insufficient: negative server-side dry-run must prove denial by the exact expected policy, including writable and metadata-changing source mounts. Source Pod exec/delete is limited to its deterministic identity-derived helper name. No source Secret access, PVC writes or automatic policy/RBAC installation is granted. Helper root privileges are an explicit opt-in, not a default. Chart copy support defaults disabled.

## Verification

- Contracts/domain and generated SDK race tests and SDK drift checks passed.
- Agent full race regression passed.
- API app/server race regression passed, including the final completion-evidence test: invalid digest/target/unverified acknowledgment rejected; valid copy acknowledgment retains Creating and strips the credential. Full API lint: zero issues.
- Runner runtime and filesystem/transport/fence race checks passed after admission metadata hardening. Full Runner lint: zero issues. Fence focused tests and vet passed; these test generated policy and transport behavior, not live CNI/admission acceptance.
- Frontend: 486 unit tests, five mocked browser cases, typecheck and lint passed. These are not a live cluster/UI acceptance test.
- Runner Helm contract tests and vendored-chart drift checks passed; source chart is 0.4.14.

## Open release and acceptance gates

1. Publish the new contracts module and align direct consumers currently pinned to v0.1.109. Local sibling-workspace checks do not prove released-module builds. Do not push dependent consumers first.
2. Implement database-aware consistent backup/restore and isolated target credentials. Active MySQL/raw DB volumes are currently blocked; test-app mysql-data is not copied.
3. Complete native reviewed source-profile/fence onboarding and non-default tenant runtime integration.
4. Implement Helm existingClaim/template binding before enabling that backend.
5. Authorize source maintenance, prepare the reviewed profile, then prove actual source/target marker data, restart persistence, retry/cancellation and cleanup in a cluster. No live copying or source mutation was performed in this iteration.

Installed release remains 0.4.705. Local commits are not deployed. No push is performed before shared verification/publication coordination.
