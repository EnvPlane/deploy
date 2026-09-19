# SM-09 port-forward API requests must bypass proxy settings

## Problem

After all disposable cluster workloads became Ready, the first API health
request through the local `kubectl port-forward` returned HTTP 401. The API
health handler itself is public; the request can be redirected through ambient
runner proxy settings before it reaches the loopback port-forward.

Failed run: [Publish latest compatible envplane umbrella release run
33001225798](https://github.com/envplane/deploy/actions/runs/33001225798).

## Resolution

Route every harness API request directly to the local port-forward with
`curl --noproxy '*'`. This affects only the test client; Agent and Runner keep
using their in-cluster Service DNS endpoint.

