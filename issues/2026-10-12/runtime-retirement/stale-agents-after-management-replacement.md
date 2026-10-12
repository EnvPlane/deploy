# Stale remote Agents keep polling the replacement management installation

Status: live operational mismatch observed; no repair/delete authorized here.
Plan chapters: 5 remote recovery, 13 reliability, 14 replacement/restore.

## Evidence

In the active 0.4.721 management database, a five-minute sample contains 20
agent_heartbeat_auth_failed events. Metadata-only grouping identifies:

- project app, agent ep-agent-c05a23617cac-envplane-agent: 10, reason not_found;
- project bethunder-local, agent envplane-agent: 10, reason not_found.

Both corresponding Agent pods are Running/Ready in bethunder-policy-candidate,
namespace envplane-system. The source bethunder-local cluster returned no pods
for the same Agent-name label query. Successful management Agent and Runner
heartbeats are also present; this is not proof that all executors are failing.
The API correctly rejects unknown identities. No token, Secret or error payload
was copied. Base applications were not modified.

## Codex implementation prompt

Define management replacement/restore recovery for existing remote runtimes.
Detect a retired project/bootstrap binding or wrong management endpoint through
bounded metadata. Present operator-reviewed reconnect versus retire actions;
never silently adopt an old identity or grant new rights. Report authenticated
readiness, not only Kubernetes Pod Ready. Repeated terminal not_found should
produce a bounded degraded/backoff state rather than indefinite high-rate
retry/audit noise. Retire only exact reviewed Helm/runtime resources and preserve
base workloads/PVCs. Test restart, expired/stale registration, alternate live
management targets and rollback. Obtain explicit authority before changing these
two live Agents or their credentials.
