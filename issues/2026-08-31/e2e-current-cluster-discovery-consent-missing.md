# E2E current-cluster discovery consent missing

## Problem

The disposable clean-install browser profile selected the current-cluster path
but did not explicitly enable its read-only discovery capability. As a result,
the control plane could not inspect namespaces, ingress classes, or storage
classes, and correctly rejected the `cluster-ready` first-run transition.

## Resolution

The dedicated E2E profile explicitly opts into only
`rbac.currentClusterDiscovery`. This creates the chart's limited read-only
ClusterRole for cluster metadata; normal and production values retain the
default disabled setting.
