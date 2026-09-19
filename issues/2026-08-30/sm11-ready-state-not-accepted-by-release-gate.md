# SM-11 release gate rejects the runtime Ready terminal state

## Problem

The clean-install environment API now reports the successful terminal state as
`ready` with a workload URL. The harness still accepts only the older
`running` spelling even though the workload rollout and URL are healthy.

## Required fix

Accept the supported Ready state (and the legacy Running spelling during the
migration window) while continuing to require a non-empty URL and Running
workload Pods.

## Resolution

The harness now accepts `ready` or `running`, requires a non-empty URL, and
still verifies the target workload Pods are Running after the API succeeds.
