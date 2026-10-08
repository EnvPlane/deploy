# Historical management installer lacks pod metrics delegation

Status: read-only diagnosis; administrator migration pending. No grants applied.

Evidence 2026-10-08: envplane/envplane-control-plane uses SA envplane-control-plane,
deployed chart label envplane-control-plane-0.3.60. Its Helm-owned ClusterRole
envplane-control-plane-same-cluster-project-executor-release-manager has no
metrics.k8s.io rules. Existing envplane-base Agent discovery Role
ep-agent-ece91a52b07f-envplane-agent-discovery-reader likewise lacks them. SAR get
and list pods.metrics.k8s.io in envplane-base for that installer returned no.
API discovery also reported no pods resource in metrics.k8s.io: **management
Metrics API availability is a separate prerequisite**, not solved by granting RBAC.

Local canonical CP RBAC template already renders get/list metrics.k8s.io pods
in executor reader and release-manager delegation. Thus this is installed historical
grant/profile migration after new Agent0.2.37 overlay, not evidence that the new
chart omits the rule. No extra broad default Node, Secret or metrics write access.

## Exact bounded profile migration command (administrator review only)

Generate a narrow namespace-only grant for the proven installer identity. Commands
below are documented, **not executed**. They do not copy the whole release-manager
ClusterRole or grant cluster-wide pod metrics. Use an exclusive private directory:

```sh
task_profile_dir=$(mktemp -d /private/tmp/management-metrics-profile.XXXXXX)
kubectl --context envplane -n envplane-base create role envplane-control-plane-metrics-discovery \
  --verb=get,list --resource=pods.metrics.k8s.io --dry-run=client -o yaml > "$task_profile_dir/role.yaml"
kubectl --context envplane -n envplane-base create rolebinding envplane-control-plane-metrics-discovery \
  --role=envplane-control-plane-metrics-discovery \
  --serviceaccount=envplane:envplane-control-plane --dry-run=client -o yaml > "$task_profile_dir/binding.yaml"
kubectl --context envplane diff -f "$task_profile_dir/role.yaml" -f "$task_profile_dir/binding.yaml"
# Only after the administrator approves the exact namespace-scoped profile:
kubectl --context envplane apply -f "$task_profile_dir/role.yaml" -f "$task_profile_dir/binding.yaml"
```

Then auth can-i get/list pods.metrics.k8s.io in envplane-base must pass for that
exact SA; metrics writes and unapproved namespaces must not gain new rights.
Use the normal reconciler/Helm upgrade to update the owned Agent discovery Role;
do not edit Agent token stores or bypass RBAC escalation checks. Roll the canonical
CP child/umbrella profile through normal release preparation afterward and review
its wider installed delegation contract independently; avoid silently reusing a
full old Helm manifest as a new broad-permission migration.

## Codex implementation prompt

Track this one-time installed-profile migration and Metrics API readiness separately.
No additional application code needed for the already present read rule. Coordinate
with parent/FinOps owner before an approved admin apply, record exact identity and
scope, then verify Agent chart upgrade and real metrics collection. Remote candidate
CNI/data/heartbeat acceptance is separate and must not be rolled back for this gap.
