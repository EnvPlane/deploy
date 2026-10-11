# Recover a stale local QA port-forward

`kubectl port-forward service/...` binds a selected Pod. A rollout can close its
sandbox; the observed local log reports a closed network namespace, websocket
closure and lost connection to the Pod. Launchd KeepAlive recovers process exits,
but does not detect a still-running forward with a dead transport.

For local QA, supervise the owned forward with explicit target configuration:

```sh
python3 scripts/supervise-local-forward.py \
  --kubeconfig /absolute/path/to/kubeconfig \
  --context kind-test --namespace envplane --service envplane-frontend \
  --local-port 3000 --remote-port 3000
```

Use this command as the launchd service command instead of bare kubectl. Stop
the existing supervisor before replacing it; never run two owners of port 3000.
The script binds loopback only, checks GET `/` with a two-second timeout and
restarts only its own child after three transport failures beyond startup grace.
HTTP errors and redirects count as reachable; there is no request replay,
credential forwarding, response-body logging or Kubernetes mutation.

This handles stale/dead forwarding, not every possible HTTP 502. The existing
relay ticket remains open for idle keepalive/ingress-hop reproduction. No live
launchd configuration was changed by the code patch. Production must use normal
Ingress, not this local QA routing adapter.
