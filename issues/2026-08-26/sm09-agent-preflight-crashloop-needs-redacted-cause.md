# SM-09 Agent preflight crashloop needs a redacted cause

## Problem

After platform pull credentials were supplied, the control-plane, frontend, and
runner became Ready. The Agent alone remained in
`Init:CrashLoopBackOff` for `control-plane-preflight`. Existing failure
diagnostics reported the pod state but not the structured preflight failure
code, leaving the cause indistinguishable between endpoint, command, and retry
configuration errors.

Failed run: [Publish latest compatible envplane umbrella release run
32997853588](https://github.com/envplane/deploy/actions/runs/32997853588).

## Resolution

On an SM-09 failure, extract only the Agent preflight JSON logger fields that
are safe by contract: message, error code/text, retryability, and attempt
bounds. Do not print container environments, logs from the running Agent, or
Kubernetes Secret resources.

