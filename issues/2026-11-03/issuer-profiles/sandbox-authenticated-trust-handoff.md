# Sandbox issuer trust handoff is incomplete

Status: blocked by issuer availability and authenticated trust handoff.

Observed 2026-11-03 after the Payment Provider owner reported GEN18 safe-stop at
16:21 Berlin. GET https://billing-sandbox.envplane.dev/v1/metadata/keys and
GET https://billing-sandbox.envplane.dev/v1/metadata/revocations both returned
HTTP 503. Financial checkout/webhook/issuance acceptance is not metadata acceptance.

The public origin and canonical TEST merchant are saved in the sandbox profile.
Production is selected by default with empty parameters; both remain disabled.
No signing key is guessed or substituted with a commercial approval key.

Codex implementation prompt:

Coordinate with the separately owned Payment Provider issuer, without duplicating
its code/deployment. Obtain the accepted GEN18-or-successor runtime receipt,
TEST merchant binding, authenticated license-signing Ed25519 public key IDs/bytes
and fingerprints, signed key metadata and revocation proof in a newly authorized
window. Check provenance independently of the HTTPS download. Populate the sandbox
profile, run chart/API key parsing and signature/revocation tests, then perform
consumer integration only under explicit deployment/activation authority. Do not
change issuer IAM, sign, renew windows or budgets, or make a payment to unblock
configuration. Preserve existing installation identity and license history.
