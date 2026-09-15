# Predecessor release rotates same-cluster bootstrap identity on restart

## Observed

In a clean Kind cluster, umbrella `0.4.243` with the published local E2E
profile starts PostgreSQL and Redis, then repeatedly crashes the control-plane:

```text
same-cluster first-start registration failed: reconcile same-cluster agent
identity: credential differs from the existing bootstrap identity; use the
explicit rotate/reissue flow
```

The singleton Agent and Runner remain in `Init:0/1` while their preflight waits
for the unavailable control-plane Service.

## Impact

`0.4.243` cannot serve as a healthy predecessor for a published
upgrade/rollback migration test. More importantly, a restart during first-run
can render a new installation unavailable instead of retaining its managed
same-cluster bootstrap identity.

## Required fix

Persist and reuse the chart-managed first-start Agent/Runner credential across
control-plane restarts. Reject only an actual operator-requested replacement;
the normal managed Secret reconciliation must be idempotent.

## Verification

1. Install a clean release with managed same-cluster registration.
2. Restart the control-plane at least twice.
3. Verify control-plane, Agent, and Runner become Ready and retain the same
   identity IDs and bootstrap credential fingerprints.
4. Run a published `N-1 → N` ConfigMap upgrade/rollback test using this
   release as predecessor.

## Codex implementation prompt

Trace chart-managed first-start Secret generation, control-plane identity
reconciliation, and restart persistence. Make the credentials stable or make
the server reuse the stored fingerprint when the managed flow is replayed. Add
unit coverage for restart idempotency and a disposable chart smoke test that
forces a control-plane restart before checking Agent/Runner readiness. Never
log raw credential values.
