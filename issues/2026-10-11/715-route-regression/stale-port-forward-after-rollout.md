# Stale local forwarding after frontend Pod rollout

Priority: P1 local QA. Status: FIXED LOCALLY; live supervisor adoption pending.

Observed local forwarding log: network namespace for the selected Pod sandbox
is closed, websocket close sent, lost connection to Pod. Service port-forward
uses a selected Pod, not a durable ingress upstream. Bare launchd KeepAlive does
not cover a stalled process whose exit has not yet occurred.

Fix: explicit kubeconfig/context/service, loopback binding, bounded read-only GET
transport health checks and restart only the supervisor-owned child. HTTP errors
do not cause restarts; application POST/PATCH requests are never replayed. No
credential, application data, namespace policy or RBAC changes.

Codex follow-up prompt: adopt the reviewed supervisor in the local launchd job,
test idle and rollout recovery with a disposable target, and verify explicit
progress readback on any interrupted write. Do not claim remaining ingress-hop
502s fixed without controlled reproduction. Never kill unrelated port owners or
switch global Kubernetes context. Production requires a normal stable Ingress.
