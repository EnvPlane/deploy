# Issuer consumer preparation, 2026-10-22

Owner: Payment Provider chat for issuer/AWS, Common chat for customer configuration
and acceptance. No issuer code, infrastructure, signer or campaign was changed.

Read the [consumer handoff](../../control-plane/docs/issuer-integration/2026-10-22-handoff.md).
The current Frankfurt deployment is a disabled TEST candidate, not a LIVE service.
Fresh accepted endpoint/trust/runtime evidence must come from the owner after its
independent approval and activation. Public origins and keys are not guessed.

## Prepared chart

Control-plane child chart 0.3.64 adds optional
`commercialization.billing.providerMode` and `merchantAccount`. The umbrella lock
and vendored child were regenerated together. Defaults do not enable a provider.
Current installation transport rejects live mode, seller credentials and duplicate
structured/env aliases. Empty new fields preserve legacy generic-env configuration.

[Pending overlay](../examples/issuer-integration.pending.yaml) contains no secrets,
real endpoint, merchant or trusted key. It keeps provider disabled. Use only as an
overlay on complete saved operator values; it is not a runnable deployment recipe.
After the owner supplies accepted metadata, the customer lane uses installation
provider and test mode. Never configure issuer private gateway or AWS credentials
for customer self-service. Rendering a compatible chart is not a release receipt.

## Local verification

- Six independent Helm render tests passed, including multiple negative cases
  for invalid/live mode, missing merchant, seller credentials and duplicate env.
- Existing vendored chart drift check passed.
- Consumer billing/license/config race regressions are recorded in the companion
  handoff after completion. These tests do not contact AWS, Stripe or a live issuer.

## Activation hold

No Helm upgrade, DNS/public route activation, trust-root installation, license
issuance/redemption, provider purchase or cross-chat message was performed.
No live-ready flag is set. Open issues retain the issuer public-route, trust and
LIVE-mode gates; they do not duplicate the issuer implementation backlog.
