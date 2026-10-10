# Durable kind-local access independent of retired management installation

Status: OPEN infrastructure follow-up; application upgrade/retirement complete.

## Evidence

Kind readiness cluster upgraded 0.4.705 to 0.4.711. Frontend/API Pods Ready, but
envplane.local returned 502 because the local frontend port-forward ended during
Pod replacement. Its domain ingress actually lived in the old Minikube context,
relaying to host.docker.internal:3000. Restarting localhost forwarding recovered
HTTP 200. Moving the relay into ingress-nginx preserved access while old product
namespaces/releases/PVCs were removed. Minikube ingress/tunnel remain routing-only.

This is a local acceptance topology limitation, not proof that production ingress
or application rollout routing is broken. Do not delete the remaining edge until
an independently verified replacement route is healthy.

## Codex implementation prompt

Provide a scoped durable local-access profile for kind that does not depend on the
retired Minikube cluster or a Pod-specific one-shot frontend port-forward. Reuse
the supported ingress/access contract where possible. Define exact ownership,
loopback exposure, canonical OAuth domain, start/stop and rollback. Verify domain
and API reachability through frontend/API rollouts, controller restart and host
restart; then retire ONLY the old edge dependency. Do not publish UI publicly,
import browser credentials, broaden project RBAC, change client PVCs or delete
other local clusters. Keep production and local acceptance support claims separate.
