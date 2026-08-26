# SM-09 fixture executor status timeout lacks redacted diagnostics

## Problem

The disposable clean-cluster gate timed out while waiting for the bootstrap
Agent status, but its cleanup output included only startup scheduling events.
It did not show the bounded status projection or the Agent runtime errors
needed to distinguish registration, heartbeat, and resource-discovery faults.

## Resolution

Preserve the chart default for `managedSameCluster`: `false` intentionally
selects the first-start registration claim, while `true` is reserved for the
project reconciler path. The harness emits bounded redacted Agent status and
runtime errors when either Agent readiness or resource discovery times out.

## Verification

Run the packaged umbrella private-registry gate and use the redacted state to
verify that the Agent reports online before the resource scan is started.
