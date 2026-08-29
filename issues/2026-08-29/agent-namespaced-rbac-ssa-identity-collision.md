# Agent namespaced RBAC objects collide during server-side apply

## Problem

The umbrella release gate fails while installing namespace-scoped Agent RBAC.
The `Role` and `RoleBinding` shared the same namespace and name. In addition,
left-trimming the end of a `range` joined the last `roleRef.name` of one item
directly to the next YAML `---` marker. Multi-namespace and multi-item renders
therefore produced an invalid combined RBAC object.

## Expected behavior

Every namespace-scoped RBAC object has an unambiguous identity and the clean
cluster release gate installs it successfully.

## Resolution

Give all generated RoleBindings a distinct `-binding` suffix, preserve the
newline between range iterations, and cover multi-namespace and multi-item
renders with chart contract tests.
