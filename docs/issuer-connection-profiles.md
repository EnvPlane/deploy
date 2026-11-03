# Customer issuer connection profiles

Both standalone and umbrella default values include
`commercialization.issuerConnection`. The umbrella path starts with
`envplane-control-plane.commercialization.issuerConnection`.

The selected profile is `production`, with empty production parameters;
`enabled: false` deliberately avoids enrolling
every fresh installation into a temporary seller campaign. No network requests,
payments, licenses or customer records are created by rendering these values.

Sandbox public defaults were collected from GEN18 evidence on 2026-11-03:
origin `https://billing-sandbox.envplane.dev`, merchant `acct_1UOFO62N7rCLLWVX`.
The canonical merchant comes from `Runtime.Commercial.Manifest` in the accepted
GEN18 runtime readback; the origin is used by the GEN18 activation health probe.
Both activation metadata endpoints returned HTTP 503 after the owner reported
safe-stop at 16:21 Berlin. Signing roots remain empty, deliberately blocking
sandbox enablement until an authenticated public trust handoff is available.
Commercial approval keys are NOT license verification roots and must not be used
as substitutes. The recorded financial TEST does not verify metadata freshness.

To prepare an installation, fill the sandbox profile from the authenticated public
handoff, then explicitly enable it in the complete operator values:

```yaml
envplane-control-plane:
  commercialization:
    issuerConnection:
      enabled: true
      profile: sandbox
      profiles:
        sandbox:
          baseURL: "https://REPLACE-WITH-ACCEPTED-BILLING-ORIGIN"
          merchantAccount: "REPLACE-WITH-CANONICAL-MERCHANT-ID"
          activationIssuerURL: "https://REPLACE-WITH-ACCEPTED-METADATA-ORIGIN"
          activationPublicKeysJSON: "[]" # Replace with authenticated public roots.
```

This example is incomplete and intentionally fails validation until trust roots
are supplied. Public keys must be authenticated independently, not trusted merely
because they were downloaded from the configured origin. The API validates the
key format and signatures; the chart only checks that the array is non-empty.
No seller Stripe credential, AWS identity or private signing key belongs here.
Do not combine enabled profiles with legacy billing/activation values or env
aliases. Existing legacy configurations still work with profiles disabled.

An enabled sandbox profile maps to provider `installation`, mode `test`, merchant,
billing origin and activation metadata/trust environment variables. Runtime,
tenant, installation, replay and signature checks remain unchanged. Render with
complete reviewed values before deployment; maintain installation identity and
accepted license history across upgrades and rollback.

## Future production switch

Store a separately accepted endpoint, merchant and public roots under
`profiles.production`. Only the selected profile is consumed; sandbox trust and
merchant settings never spill into production. The selector is `profile: production`.
The current consumer is TEST-only: enabling production fails closed with a clear
error. A separately reviewed LIVE-compatible consumer/chart release must remove
that gate before the switch is usable. Changing the selector is not LIVE approval.

GEN18 financial TEST on 2026-11-03 does not establish LIVE readiness or customer
redemption acceptance. Temporary runtime windows and credentials must never be
compiled into shared chart defaults. Connecting a running installation, issuing or
redeeming a license and extending a sandbox window are separate operator actions.
