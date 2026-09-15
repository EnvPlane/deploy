# Vendored webhook chart is stale relative to deploy source

## Observed

`bash scripts/check-vendored-chart-drift.sh` reports drift between the
repository webhook chart and vendored `envplane-webhook-0.1.2.tgz`.

The source chart now includes the optional `ENVPLANE_GITHUB_WEBHOOK_SECRET`
reference and receiver-token contract changes, but the packaged dependency
does not.

## Impact

The deploy release gate cannot publish an umbrella chart while its checked-in
child chart and vendored OCI artifact disagree. Publishing current deploy
commits would predictably fail CI.

## Required release sequence

1. Bump and publish `envplane-webhook` from its source repository through its
   normal CI workflow.
2. Update the umbrella dependency/version and vendored archive in `deploy`.
3. Run `check-vendored-chart-drift.sh`, chart contracts, and the release gate.

## Codex implementation prompt

Find the webhook chart source release workflow. Increment the child chart
version, publish the signed OCI chart from CI, then update the deploy umbrella
dependency using the normal dependency-refresh automation. Do not manually
replace a vendored archive without a corresponding published child release.
