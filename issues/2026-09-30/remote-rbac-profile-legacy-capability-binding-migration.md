# Admission policy blocks safe removal of legacy Agent capability bindings

## Defect

The current remote RBAC profile protects ClusterRoleBinding creation correctly,
but its delete rule only allows the fixed capability roles. A Helm upgrade from
the legacy release-named Agent role therefore cannot remove its own existing
`ep-agent-*-envplane-agent-cluster-capability-reader` binding. The upgrade
fails after creating the replacement auth PVC.

## Implementation prompt

Permit deletion only for a legacy binding whose name and roleRef exactly match
the legacy Agent capability-binding pattern, whose labels prove Helm ownership
and EnvPlane cluster-agent component, and whose subject is the profile's
runtime ServiceAccount namespace. Keep creation and updates restricted to the
three fixed read-only roles. Add renderer contract coverage for both the
allowed migration pattern and the absence of broad legacy permissions.
