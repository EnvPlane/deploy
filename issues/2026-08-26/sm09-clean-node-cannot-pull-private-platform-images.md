# SM-09 clean node cannot pull private platform images

## Problem

The release workflow authenticates Docker on the GitHub runner, but the fresh
Kind node has neither those credentials nor cached platform images. All private
GHCR platform Deployments reached `ProgressDeadlineExceeded`, so the harness
never reached Secret materialization assertions.

Failed run: [Publish latest compatible envplane umbrella release run
32996405815](https://github.com/envplane/deploy/actions/runs/32996405815).

## Resolution

Create the disposable release namespace and a namespaced pull Secret from the
runner's existing Docker config without printing it. Bind that Secret only to
the platform subcharts. Keep the private application image absent from the node
so its before/after materialization assertion remains valid. Emit only redacted
pod and warning-event diagnostics when the harness fails.

