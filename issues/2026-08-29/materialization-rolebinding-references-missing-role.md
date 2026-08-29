# Materialization RoleBindings reference missing Roles

## Summary

The SM-09 release gate renders materialization source and target Roles with a
`-binding` suffix, while the corresponding RoleBindings refer to Role names
without that suffix. Kubernetes accepts the manifests, but the Agent receives
403 responses when it reads an approved source Secret because the binding does
not grant the intended Role.

## Impact

- `encrypted_clone` cannot read its approved source Secret.
- The private-registry lifecycle gate fails before exercising its negative
  cases.
- Published Agent chart `0.2.18` contains ineffective materialization RBAC.

## Expected fix

- Keep Role names stable and give only RoleBinding objects the distinct
  `-binding` suffix.
- Add chart contract assertions that every materialization RoleBinding
  `roleRef.name` resolves to a rendered Role.
- Publish a patched Agent chart and update the umbrella dependency pin.
