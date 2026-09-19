# Umbrella release gate cannot read private compatible source repositories

## Problem

The release workflow checks out the Agent and frontend revisions selected by
the signed compatibility manifest with the deploy repository's `github.token`.
That token has no cross-repository read scope, so private source checkouts fail
with a misleading repository-not-found error before the release gate runs.

## Required fix

Use the automation GitHub App token or the existing automation PAT with
contents-read scope for cross-repository release-gate checkouts.

## Resolution

The workflow now selects the existing automation App/PAT credential, mints a
contents-read App token when available, and uses that token for both
compatibility-manifest source checkouts.
