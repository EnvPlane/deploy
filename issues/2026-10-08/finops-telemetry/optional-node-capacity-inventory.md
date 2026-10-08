# Explicit GPU Node capacity inventory chart/profile contract

Status: implemented locally, no live changes or push.

## Configuration

Agent chart: boolean rbac.discovery.nodeInventoryEnabled defaults false, validated
by values.schema.json. Runtime ENVPLANE_FINOPS_NODE_INVENTORY_ENABLED mirrors it.
When true, the discovery capability ClusterRole grants only get/list core nodes;
namespace and explicit cluster discovery modes both keep it disabled by default.
No nodes/proxy, nodes/stats, exec, watch or write access is granted by this option.

Remote administrator profile: pass --finops-node-inventory when enabling the same
chart option. It adds exactly that node-read rule to the existing stable capability
parent; the installer's existing bounded bind contract remains unchanged. Role
names derive from cluster ID, never fixed project names. If using pre-installed
existingClusterRoles, the administrator must render/apply this opt-in profile
before installing the enabled Agent, not repair permissions after a Helm failure.
Existing namespace discovery/metrics delegation and Runner write rights unchanged.

## Codex implementation prompt / acceptance

Parent owns runtime onboarding requirements and same-cluster install orchestration.
Propagate this explicit opt-in value to Agent chart values and validate get/list
nodes only on the chosen installer capability contract before enabling runtime
inventory. For same-cluster dynamic installers, verify their corresponding
delegated cluster-capability role includes this optional read contract; do not
silently broaden default control-plane/Agent Node access. Upgrade child chart
versions and umbrella dependencies together during parent release preparation.
Repeat actual capacity telemetry with missing GPU/provider treated as unknown,
without pretending capacity is measured utilization. Exact HTTPS Prometheus origin
and CA configuration remain the Agent runtime contract; no insecure URLs or hidden
node-subresource workaround. Existing live manual grants are not modified here.
