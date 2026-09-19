# Install-flow policy is not mounted from the signed manifest

The umbrella compatibility manifest now declares first-run and activation
contract versions plus rollout policy. The control-plane chart does not yet
mount that signed declaration, so a values-only rollout setting cannot be
checked against the selected release contract at runtime.

## Resolved

Deploy commit `0f34b26` renders the immutable revision-scoped
`<release>-release-compatibility-r<revision>` ConfigMap and mounts it
read-only at `/etc/envplane/release-compatibility` in the control-plane.
The signed chart guard rejects contract/mode values that differ from the
manifest.

Control-plane commit `15815e3` validates the mounted contract at startup,
before stores or migrations are opened. It fails closed for a first-run,
activation, or rollout-mode mismatch.

Chart rendering tests cover the mount and conflicting values. The published
ConfigMap upgrade harness verifies upgrade, rollback to the predecessor, and
rollback back to the current immutable release map.
