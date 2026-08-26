# SM-09 must poll the authoritative Agent scan status

## Problem

After starting a resource scan, the harness polled the generic Bootstrap
session data. Production SQL can keep scan reports in its sidecar store, while
the Agent status endpoint provides the hydrated authoritative scan state.

## Resolution

Poll `bootstrap-session/agent-status` and require its top-level
`resourceScanStatus` to reach `completed` before compilation.
