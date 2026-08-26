# SM-09 Agent namespace metadata RBAC missing

## Problem

The Agent's selected-namespace sync reads the corresponding cluster-scoped
Namespace object. The disposable profile rendered namespaced workload Roles
only, so Kubernetes correctly rejected that metadata request with 403.

## Resolution

Add an opt-in `namespaceMetadataRead` capability. It creates a ClusterRole
with only `get` on `namespaces` and `resourceNames` restricted to the selected
namespace allowlist. The SM-09 profile enables this capability without
granting namespace list/watch, cluster capability discovery, or Secret access.

## Verification

Render the Agent chart and confirm the allowlisted Namespace GET rule. Run the
private-registry lifecycle gate and verify the Agent reports its resource scan.
