# SM-09 overlay leaves dependent namespaces stale

## Problem

The SM-09 overlay changes the E2E fixture base, feature, and release namespaces,
but the canonical local profile also embeds those namespaces in Agent watch
configuration, Runner writer RBAC, same-cluster endpoints, Runner config URL,
and first-start registration. Helm attempted to create Runner RBAC in the stale
`envplane-e2e-feature` namespace, which no longer existed.

Failed run: [Publish latest compatible EnvPlane umbrella release run
32996004531](https://github.com/EnvPlane/deploy/actions/runs/32996004531).

## Resolution

Override every namespace-dependent consumer together with the fixture
namespaces. Keep the release namespace, Agent and Runner endpoints, Runner
registration/config URL, watch scope, and feature writer RBAC consistent.

