# Vendored agent chart is stale after materialization RBAC change

The umbrella chart still pins and vendors `envplane-agent` 0.2.13 after the
source chart added Secret materialization RBAC at 0.2.14. The release drift
gate blocks publication until the dependency and archive are updated together.

## Resolution

Pin the umbrella dependency and bootstrap metadata to 0.2.14, regenerate the
lockfile and vendor archive, and publish the final immutable runtime images.

## Status

Resolved in the coordinated Secret materialization release.
