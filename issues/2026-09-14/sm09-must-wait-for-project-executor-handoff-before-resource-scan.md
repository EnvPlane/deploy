# SM-09 must wait for project-executor handoff before resource scan

## Observed

Against published umbrella `0.4.243`, the disposable SM-09 gate starts a
resource scan as soon as any first-start Agent reports connected. The singleton
bootstrap Agent can satisfy that condition before the project-scoped Agent and
Runner complete handoff. The scan is then produced with bootstrap scope and
Bootstrap compilation rejects its dependency graph.

## Expected

The gate must exercise the product path it claims to verify: project-scoped
Agent and Runner identities must be online, the bootstrap lifecycle marker
must be `retired`, and the singleton Agent/Runner Deployments must be scaled to
zero before the resource scan is scheduled.

## Implementation prompt

Add a bounded handoff wait to
`scripts/private-registry-secret-materialization-e2e.sh`. Query both runtime
status APIs, verify project-owned executor identities, inspect the lifecycle
ConfigMap and bootstrap Deployment replica counts, then start the scan. Keep
all diagnostics redacted and add a shell-contract regression test if the
repository has an existing pattern for this harness.

## Acceptance criteria

- SM-09 cannot accept a singleton bootstrap Agent as readiness evidence.
- The gate verifies both singleton runtime Deployments are at zero replicas.
- The first resource scan is dispatched only after the project-scoped pair is
  authoritative.
