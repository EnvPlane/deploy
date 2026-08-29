# Release gate selected an unvalidated Helm major

## Problem

`azure/setup-helm` was unpinned, so the release workflow silently moved from
Helm 3 to Helm 4. Helm 4's server-side apply path mis-associated the
namespace-scoped Agent `RoleBinding` payload with its `Role`, causing the clean
cluster gate to fail on `roleRef` and `subjects` schema fields.

## Expected behavior

The mandatory release gate uses the same supported Helm major advertised by
the public install contract and does not drift when a new major becomes the
action default.

## Resolution

Pin the release workflow to the current supported Helm 3 patch and enforce the
pin in the workflow contract test.
