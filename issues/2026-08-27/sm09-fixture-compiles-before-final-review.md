# SM-09 fixture compiles before final review

## Problem

The disposable release harness proceeded from Agent registration directly to
resource scan and compile. The chart-managed fixture advances the Bootstrap
session to final review asynchronously, so a fast clean cluster could receive
a public compile request while the session still had an earlier wizard step.

## Resolution

Wait for the authenticated Bootstrap-session API to report the persisted final
review step before starting the resource-scan and compile path.
