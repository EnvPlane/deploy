# Public management endpoint health route bypasses the frontend

## Evidence

With EnvPlane `0.4.561`, a remote cluster configured with the public
Cloudflare endpoint reaches the installation preflight but the managed Agent
cannot become Ready. The Agent checks
`GET <management-endpoint>/api/v1/health`; the public Ingress returns `404`.

The control-plane Service returns `200` for that exact path. The umbrella
Ingress and Gateway route the broad `/api` prefix to the frontend, which is
correct for browser-session proxying but does not expose the unauthenticated
runtime health endpoint required before an Agent can register.

## Required implementation

1. Route the exact `/api/v1/health` path to the control-plane Service before
   the existing `/api` browser-proxy route in both Ingress and Gateway modes.
2. Keep all other `/api` paths directed to the frontend; do not expose the
   control-plane's authenticated API surface directly.
3. Add chart contracts proving the exact health route maps to the
   control-plane and the wider browser API route still maps to the frontend.
4. Verify a public target-Pod connectivity preflight can reach the health
   endpoint and complete the managed Agent/Runner rollout.

## Codex implementation prompt

Implement an exact public management-endpoint health route in
`deploy/helm/envplane/templates/access.yaml`. Preserve same-origin browser
API proxying and make both Ingress and Gateway routing explicit and ordered.
Add focused chart-contract tests, run the deploy chart test suite, then test
the remote cluster preflight through an external endpoint.
