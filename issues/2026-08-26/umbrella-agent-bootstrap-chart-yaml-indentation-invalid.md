# Umbrella Agent bootstrap chart YAML indentation invalid

## Problem

The Agent child-chart version update changed the indentation of
`envplane-control-plane.agentBootstrap.chart`. The release helper matches the
canonical YAML path and therefore rejected the malformed values file before
the mandatory SM-09 gate could run.

## Resolution

Restore the canonical indentation for `ref` and `version`. The dependency
update regression script now runs with release validation so this path is
exercised before publishing an umbrella artifact.

## Verification

Run `scripts/test-umbrella-chart-dependency-update.sh` and the umbrella chart
tests, then confirm the release workflow can select OCI dependencies.
