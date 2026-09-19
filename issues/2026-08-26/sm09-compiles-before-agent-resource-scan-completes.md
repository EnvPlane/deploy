# SM-09 compiles before the Agent resource scan completes

## Problem

The clean-cluster harness sent the encrypted-clone Bootstrap compile request
immediately after the Agent Deployment rolled out. The compile contract
correctly rejected it while the required resource scan was incomplete.

## Resolution

Wait for the chart-managed fixture's Agent scan to report `completed` through
the authenticated API before saving the Secret strategy and compiling.
