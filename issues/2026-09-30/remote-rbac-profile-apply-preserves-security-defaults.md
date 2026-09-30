# Remote RBAC profile reapply must preserve security defaults

## Defect

The generated remote-cluster RBAC profile omitted the protected runtime
namespace labels and `automountServiceAccountToken: false`. Applying a newer
profile to an older installation could therefore remove previously managed
Pod Security labels and re-enable automatic ServiceAccount token mounting.

## Implementation prompt

Render the runtime namespace with the EnvPlane ownership and restricted Pod
Security labels, and render the installer ServiceAccount with automatic token
mounting disabled. Extend the renderer contract test to assert these defaults.
Re-render the production profile and compare it before application. Do not
weaken the profile to avoid an RBAC validation failure.
