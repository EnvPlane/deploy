# Runner chart publication must bump when RBAC changes

## Evidence

The canonical Runner chart changed managed-remote namespace RBAC while its
version remained `0.4.11`. Release compatibility selected the already-published
`0.4.11` OCI artifact, so the release-gate umbrella rendered an older RBAC
contract than the canonical source.

## Implementation prompt

Bump the immutable child chart version whenever rendered RBAC or workload
content changes, synchronize the umbrella dependency, lock file, and vendored
archive, and publish the new OCI version before compatibility release
resolution. Add a contract check preventing source changes from being paired
with an unchanged published chart version.
