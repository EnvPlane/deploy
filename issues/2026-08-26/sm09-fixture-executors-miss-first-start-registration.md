# SM-09 fixture executors miss first-start registration

## Problem

The disposable clean-cluster profile configured a managed first-start
registration claim but left both chart-managed executors in their default
standalone mode. The charts therefore omitted the registration token mount.
The Agent could not establish its runtime identity, and the release gate
timed out waiting for the bootstrap Agent status.

## Resolution

Enable `managedSameCluster` for the Agent and Runner in the disposable
profile. The harness also emits bounded redacted Agent status and runtime
errors when either Agent readiness or resource discovery times out.

## Verification

Run the packaged umbrella private-registry gate and verify that the Agent
reports online before the resource scan is started.
