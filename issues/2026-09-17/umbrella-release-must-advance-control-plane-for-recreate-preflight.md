# Umbrella release does not deliver the current control-plane recreate preflight

## Observed behavior

After control-plane commits `0781609` and `64b5837` were pushed, umbrella
release `0.4.256` still resolved `envplane-control-plane` dependency version
`0.3.54`. A UI Recreate request returned `202` and created the preview
namespace plus Agent/Runner RBAC before delayed reconciliation failed.

## Expected behavior

An umbrella release advertised for a fix must vendor a newly published
control-plane chart whose API image contains the requested commit. The release
verification should expose the resolved component chart versions and image
digests so this can be audited before deployment.

## Implementation prompt

Update the release automation so an umbrella tag that includes a
control-plane fix first publishes and pins the matching control-plane chart
version. Add a CI contract that fails when a declared control-plane commit is
absent from the vendored chart/image metadata.

## Acceptance criteria

- The next umbrella release pins a control-plane chart newer than `0.3.54`.
- Recreate rejects the invalid Full service routing synchronously with no
  namespace, RBAC, secret-materialization command, or Runner command created.
- Release metadata identifies the resolved control-plane chart and API digest.
