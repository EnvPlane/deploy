# Helm 4 upgrade field-manager conflict

## Evidence

During isolated upgrade from umbrella 0.4.370 to 0.4.372, Helm 4.3.0's
server-side apply conflicted with `kubectl-set` ownership of the API image.
Automatic rollback also conflicted with `platform-reconciler` ownership of
`status.json` in a revision-scoped ConfigMap. The release was left in a failed
history state. Repeating the upgrade with `--server-side=false` succeeded.

## Implementation prompt

Keep the documented operator-values reset behavior. When the Helm client
supports the server-side flag, make the supported umbrella upgrade wrapper use
client-side updates. Preserve Helm 3 compatibility and add a wrapper contract
test. Explain the compatibility behavior in installation documentation.

## Acceptance criteria

- Helm 4 wrapper upgrades do not conflict with runtime-owned status fields.
- Helm 3 clients without the flag continue using their existing behavior.
- The wrapper still resets chart defaults and retains operator values.
- The isolated 0.4.372 upgrade and remote runtime health checks pass.
