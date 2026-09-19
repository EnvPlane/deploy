# SM-09 values overlay overwrites the E2E profile

## Problem

The private-registry release harness copied `values-e2e-local.yaml` and then
appended new `global`, `envplane-agent`, and `envplane-control-plane` mappings to
the same YAML document. Duplicate top-level keys replace or ambiguously merge
the original profile. In the mandatory umbrella run this removed
`envplane-control-plane.postgres.tls.enabled=false`, and Helm failed because no
PostgreSQL TLS CA Secret exists in the disposable cluster.

Failed run: [Publish latest compatible EnvPlane umbrella release run
32993107620](https://github.com/EnvPlane/deploy/actions/runs/32993107620).

## Resolution

Keep the canonical local E2E profile unchanged and pass SM-09 customizations as
a second Helm values file. Helm then performs an explicit recursive overlay
without duplicate YAML keys.

