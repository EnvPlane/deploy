# Management project Runner fails authentication

Status: open; diagnosis required before changing credentials.

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
