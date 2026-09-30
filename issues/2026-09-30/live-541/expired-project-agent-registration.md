# Project agents cannot recover after bootstrap credential expiry

Status: diagnosed; readiness fix tested locally; live RBAC repair and recovery verification pending.
Release: umbrella 0.4.541, management context envplane, target bethunder-local.

## Evidence

On 2026-09-30, all five management deployments are available. Target namespace
envplane-system has 62 Bound PVCs. Two project agents are CrashLoopBackOff:
ep-agent-1e9695035d38 and ep-agent-c05a23617cac. Both report registration HTTP 401:
`expired bootstrap registration credential: registration token is expired`.
The affected pods predate the umbrella upgrade; this is not proof of a new
0.4.541 regression. Do not delete PVCs or broaden RBAC to resolve this.

## Implementation prompt

Trace project executor reconciliation and durable agent credential recovery.
Determine why these agents still attempt registration using expired bootstrap
credentials. Reuse valid persisted identity when available; otherwise issue a
fresh short-lived project-scoped credential through the authorized reconciliation
path. Preserve tenant/project isolation, expiry checks and credential secrecy.
Add tests for restart after expiry, missing persisted identity and concurrent
reconciliation. Verify recovery live without modifying application workloads.

## Related verification

Local UI and the newly created temporary Cloudflare tunnel return HTTP 200.
Public API authorization probing was blocked by tool safety review and was not
performed. Remote lifecycle E2E remains blocked by agent registration.

## Diagnosis and local fix

The persisted recovery intents exist for both projects. Management logs report
`remote Kubernetes access validation failed`; RemoteAccess is False due to RBAC.
An authenticated endpoint heartbeat incorrectly overwrote the phase to healthy
and cleared the repair action without resolving that condition.

Read-only impersonation checks confirm that the installer ServiceAccount
`envplane-system/envplane-remote-cluster-bethunder-local` lacks bind and update
on `envplane-remote-cluster-bethunder-local-namespace-metadata-reader`.
Do not bypass credential validation or token expiry to recover.

The control-plane fix preserves the failed access status through endpoint
reports and rejects contradictory healthy status in readiness evaluation.
Regression tests cover recovery after access validation and replacement of an
expired token while a recovery intent is pending. All tests in internal/app,
internal/remoteclusters and internal/server passed locally.

Remaining live step: review and apply the current installer RBAC profile, then
verify queued reconciliation issues credentials and both agents heartbeat.
This ticket is not closed until that live check succeeds.
