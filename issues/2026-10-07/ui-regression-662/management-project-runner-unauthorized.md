# Management project Runner fails authentication

Status: fixed in control-plane code and recovered live with a local API hotfix; published release inclusion pending.

## Resolution

Runtime credentials expired after an offline interval. The first-start project had handed off to project executors, but startup and recovery still excluded its project ID. Ownership-aware reconciliation and explicit expiry rotation fixed the dead end. Existing Agent/Runner release names retained, auth claims r2, both Pods 1/1 Running with zero restarts; API restart preserved them. No RBAC expansion, token disclosure, or remote-cluster credential changes.

See control-plane/issues/2026-10-07/management-runtime-recovery/first-start-project-handoff-recovery.md. The current API uses temporary local image envplane-api-management-recovery:662-20261007-v2; umbrella 0.4.662 itself does not contain the new code.

## Observed

Context envplane, namespace envplane-executors:
deployment ep-runner-962bba4c4f3a-envplane-runner is 0/1 ready.
Pod is CrashLoopBackOff with 91 restarts; this preceded umbrella 0.4.662 upgrade.
Previous runner log classified as unauthorized; no raw credential-bearing logs retained.
Sibling project Agent is ready. Remote bethunder-local is healthy; do not conflate targets.

## Implementation prompt

Trace same-cluster project Runner registration and credential reconciliation in control-plane/runner/deploy. Determine whether persisted registration credentials, project/tenant binding, or rotation reconciliation diverge. Compare safe references and hashes only; never expose tokens. Add regression tests for API restart and credential reconciliation. Implement a narrow idempotent repair only after identifying the cause, without widening RBAC, disabling authentication, or changing remote cluster credentials. Preserve project-owned release names and base workloads. Verify authenticated Runner heartbeat and readiness on the affected target after an approved repair.

## Acceptance

- Existing project Runner recovers with valid scoped credentials and fresh heartbeat.
- No plaintext tokens in logs/UI/tickets or repository.
- API restart and registration rotation tests demonstrate recovery without duplicate releases.
- No new cluster-wide privileges or impact to bethunder-local.
