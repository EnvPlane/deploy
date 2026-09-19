# Release gate resolves a stale control-plane chart version

## Problem

The release workflow replaces development `file://` dependencies with published
OCI charts. Updating the canonical control-plane chart without advancing its
chart version therefore caused SM-09 to resolve the previously published
`0.3.45` archive, which still applied a 14-day activation grace period.

## Resolution

Advance the control-plane chart to `0.3.46`, update the umbrella dependency,
and regenerate its lockfile and vendored archive. The release workflow will
then publish and consume the immutable chart that contains the fix.
