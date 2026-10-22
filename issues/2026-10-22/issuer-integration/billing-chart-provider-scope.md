# Billing chart lacks explicit provider mode and merchant scope

Status: chart integration prepared locally; real issuer acceptance pending.

## Evidence

Customer API main supports billing provider installation with explicit test mode,
canonical merchant, persisted installation identity and no seller credentials.
The chart exposes provider/baseURL but lacks structured providerMode and
merchantAccount. Relying on generic environment overrides makes mode isolation
and installation onboarding harder to review.

## Implementation and Codex follow-up prompt

Add explicit optional mode/merchant values without overriding legacy env defaults.
Reject duplicate aliases, unsupported modes, live installation transport and seller
credentials in the customer installation lane. Render and negative-test the exact
chart. Do not expose private gateway/signer, copy seller tokens, grant customer AWS
roles or enable the separate Frankfurt application. Complete actual public-route,
merchant, trusted-key and fresh tenant enrollment acceptance only after the issuer
team supplies an admitted running TEST endpoint. LIVE remains independently gated.
