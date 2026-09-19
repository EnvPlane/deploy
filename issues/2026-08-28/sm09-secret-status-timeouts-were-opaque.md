# SM-09 Secret status timeouts were opaque

The private-registry lifecycle gate waited for failed and ready Secret plan
states using a final silent `jq` assertion. When the runtime returned a valid
but unexpected redacted state, CI exposed only exit code 1 and Kubernetes pod
diagnostics, not the plan state that caused the timeout.

## Resolution

Emit the public plan state and each item's identifier, state, and redacted
error code before failing either wait. Secret values, digests, namespace names,
leases, and credentials remain excluded.
