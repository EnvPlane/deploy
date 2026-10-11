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

## October 11 local-access restoration

The kind 0.4.711 runtime and ingress were healthy, but no localhost:3000 listener
remained and the domain returned 502. A terminal-detached process did not survive.
A user-scoped launchd job `dev.envplane.kind-local-forward` now supervises only
the exact kind frontend port-forward, bound to 127.0.0.1:3000. KeepAlive and a
five-second throttle recover process exits/Pod replacement. HTTP 200 and the
local listener were confirmed after the launching command returned.

This is a scoped operational fix, not completion of the independent domain-route
ticket. Minikube ingress/tunnel still provide the edge; the launchd registration
and private kubeconfig are session/local assets, not a validated reboot-safe
production configuration. No application values, Secret data or PVCs changed.
