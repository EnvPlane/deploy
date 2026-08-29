# Agent namespaced RBAC objects collide during server-side apply

## Problem

The umbrella release gate fails while installing namespace-scoped Agent RBAC.
The `Role` and `RoleBinding` share the same namespace and name. Helm's
server-side apply path associates the binding payload with the Role and rejects
the undeclared `subjects` field.

## Expected behavior

Every namespace-scoped RBAC object has an unambiguous identity and the clean
cluster release gate installs it successfully.

## Resolution

Give discovery RoleBindings a distinct `-binding` suffix and cover the rendered
identities with a chart contract test.
