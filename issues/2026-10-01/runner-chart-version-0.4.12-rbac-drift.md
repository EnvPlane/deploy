# Runner chart 0.4.12 became stale after another RBAC change

The canonical Runner chart gained additional Flux discovery permissions after
`0.4.12` was published. Because the chart version did not change, the release
resolver selected an immutable OCI archive whose RBAC payload differed from the
canonical source.

## Remediation

Bump the Runner chart to `0.4.13`, regenerate the umbrella lock and vendored
archive, and publish the new child chart before the next umbrella release.
