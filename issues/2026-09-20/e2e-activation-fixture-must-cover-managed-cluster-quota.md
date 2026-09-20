# E2E activation fixture omitted the managed-cluster entitlement

## Observed

The isolated Remote Cluster onboarding test was correctly blocked by the free plan's managed-cluster quota. The release-test activation fixture could issue project and environment limits but could not grant `clusters.managed.max`.

## Impact

There was no supported test-only way to validate Remote Cluster onboarding under an entitlement that permits it.

## Fix

Add a non-negative `--remote-clusters-max` flag to the disposable activation-code generator and include the canonical managed-cluster limit in signed grants.

## Validation

Verify the signed envelope contains the requested canonical limit and activate a disposable code against an isolated installation.
