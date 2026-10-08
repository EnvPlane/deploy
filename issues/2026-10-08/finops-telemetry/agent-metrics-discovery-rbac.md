# Namespaced Agent pod metrics discovery and delegation

Status: implemented locally; live acceptance pending parent FinOps integration.

Agent telemetry GET/LIST metrics.k8s.io pods lacked the chart discovery grants.
Added only get/list pods in that API group to discovery rules, remote installer
discovery-parent and managed namespace reader, plus same-cluster executor and
release-manager delegated reader contracts. No metrics watch/write or node metrics,
no new Secret permissions, no Runner writer changes. Remote parent ClusterRole is
bound using namespaced RoleBindings; explicit Agent cluster discovery opt-in retains
its existing scope. Same-cluster installer already delegates discovery for dynamic
project namespaces; this addition follows that existing read boundary.

## Codex implementation prompt / remaining acceptance

Parent owns control-plane runtime access requirement checks. Verify namespaced
get/list pod metrics requirements match these charts. After an explicitly approved
release/install, test Agent telemetry in allowed namespaces and forbidden namespace
denial; distinguish missing Metrics API and missing RBAC from zero usage. No live
RBAC patch or metrics-server installation is authorized by this local code change.
Use chart scoped metrics and renderer anti-escalation regression tests. Preserve
all runtime credentials and existing workloads. Prepare child chart version bumps
and umbrella dependency publication together in the parent's release iteration.
