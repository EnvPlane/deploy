# Source review and local forwarding fixes after 0.4.717

## Code fixes

The source-profile projection previously called the execution discovery helper,
requiring target Secret strategies before the wizard could reach that step.
Source-only discovery now omits that later target requirement; compilation and
execution continue rejecting absent, cloned or shared target credentials.
Source UID/image/TLS/backup identities, approval and installation gates remain.

The local forwarding log independently shows closed Pod sandbox and websocket
errors during a rollout. The new explicit-target loopback supervisor detects
dead or stalled forwarding and restarts only its own child. It issues only safe
GET probes, treats HTTP failures as reachable, logs no bodies or credentials,
and does not replay writes. The live launchd job was not changed.

## Verification

- Targeted SQL review/restore/approval tests with `-race`: PASS.
- Full server package with the current local contracts source: PASS.
- Published-contract server suite excluding the known OpenAPI mismatch: PASS.
- `go vet ./internal/server`: PASS in the clean isolated copy.
- Six local-forward supervisor tests: PASS.
- Whitespace/diff check and control-plane brand check: PASS.

The normal working directory contains separate uncommitted billing changes
whose new contract symbols are not available; these were not modified or staged.
Tests used a clean temporary checkout with only this iteration's source changes.
The full published-contract suite fails its pre-existing served OpenAPI equality
test, also reproduced in untouched HEAD. This is tracked by
`control-plane/issues/2026-10-11/payment-tax-contract/PAY-003-contracts-publication-and-pins.md`.
Do not mistake local workspace success for a published-consumer or hosted CI pass.

## Still pending

Deploy the fixed API and repeat the source-profile UI approval workflow. Confirm
native backup/restore, target data equality and independent credentials after
source approval and fresh CNI proof. Adopt the local supervisor and test actual
idle/rollout forwarding; other ingress-hop HTTP 502 causes remain unisolated.
Publish the reviewed contracts and update consumer pins before release acceptance.
