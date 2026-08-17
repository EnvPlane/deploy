#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(mktemp)"
agent_rendered="$(mktemp)"
runner_rendered="$(mktemp)"
trap 'rm -f "$rendered" "$agent_rendered" "$runner_rendered"' EXIT

helm template envpilot "$chart_dir" \
  --set 'postgres.tls.enabled=false' \
  --set 'global.envpilot.firstStartRegistration.mode=managed' \
  --set 'global.envpilot.firstStartRegistration.project.id=envpilot' \
  --set 'global.envpilot.firstStartRegistration.project.productId=generic' \
  --set 'global.envpilot.firstStartRegistration.agent.id=envpilot-agent' \
  --set 'global.envpilot.firstStartRegistration.runner.id=envpilot-runner' \
  --set 'global.envpilot.firstStartRegistration.runner.deploymentMode=helm' \
  --set 'global.envpilot.firstStartRegistration.cluster.id=bethunder-local' \
  --set 'global.envpilot.sameClusterProjectExecutors.enabled=true' \
  --set 'global.envpilot.sameClusterProjectExecutors.namespace=envpilot-executors' \
  --set 'global.envpilot.sameClusterProjectExecutors.discovery.namespaces[0]=envpilot-e2e-base' \
  --set 'global.envpilot.sameClusterProjectExecutors.discovery.namespaces[1]=envpilot-shared' \
  --set 'global.envpilot.sameClusterProjectExecutors.registry.existingSecret=envpilot-ghcr' \
  --set 'global.envpilot.sameClusterProjectExecutors.registry.imagePullSecret=envpilot-ghcr' \
  --set 'rbac.sameClusterProjectExecutors.enabled=true' \
  --set 'rbac.sameClusterProjectExecutors.namespace=envpilot-executors' >"$rendered"

rg -Fq 'name: ENVPILOT_SAME_CLUSTER_PROJECT_EXECUTORS_ENABLED' "$rendered"
rg -Fq 'value: "true"' "$rendered"
rg -Fq 'name: ENVPILOT_SAME_CLUSTER_PROJECT_EXECUTORS_NAMESPACE' "$rendered"
rg -Fq 'value: "envpilot-executors"' "$rendered"
rg -Fq 'name: ENVPILOT_SAME_CLUSTER_PROJECT_EXECUTORS_IMAGE_PULL_SECRET' "$rendered"
rg -Fq 'value: "envpilot-ghcr"' "$rendered"
rg -Fq 'name: ENVPILOT_SAME_CLUSTER_PROJECT_EXECUTORS_DISCOVERY_NAMESPACES' "$rendered"
rg -Fq 'value: "envpilot-e2e-base,envpilot-shared"' "$rendered"
rg -Fq 'name: HOME' "$rendered"
rg -Fq 'value: /tmp/envpilot-home' "$rendered"
rg -Fq 'name: XDG_CACHE_HOME' "$rendered"
rg -Fq 'value: /tmp/envpilot-home/cache' "$rendered"
rg -Fq 'name: HELM_REGISTRY_CONFIG' "$rendered"
rg -Fq 'value: /etc/envpilot/helm-registry/config.json' "$rendered"
rg -Fq 'name: executor-registry-config' "$rendered"
rg -Fq 'secretName: "envpilot-ghcr"' "$rendered"
rg -Fq 'key: .dockerconfigjson' "$rendered"
# The registry Secret remains operator-managed. The chart can reference its
# name, but must never render a credential-bearing Secret for it.
! rg -Uq 'kind: Secret\nmetadata:\n  name: "envpilot-ghcr"' "$rendered"
! rg -q 'dockerconfigjson:' "$rendered"
rg -Fq 'name: envpilot-control-plane-same-cluster-project-executors' "$rendered"
rg -Fq 'namespace: "envpilot-executors"' "$rendered"
rg -Fq 'helm.sh/resource-policy: keep' "$rendered"
# Kubernetes anti-escalation requires the control plane to hold the exact
# namespaced rules it delegates to project-owned Agent and Runner releases.
# The Runner writer contract remains limited to the executor namespace.
rg -Fq 'resources: ["configmaps", "endpoints", "events", "limitranges", "resourcequotas", "services"]' "$rendered"
rg -Fq 'resources: ["configmaps", "events", "limitranges", "resourcequotas", "services"]' "$rendered"
rg -Fq 'resources: ["statefulsets"]' "$rendered"
rg -Fq 'resources: ["cronjobs", "jobs"]' "$rendered"
rg -Fq 'resources: ["ingresses"]' "$rendered"
rg -Fq 'verbs: ["create", "update", "patch", "delete"]' "$rendered"
rg -Fq 'resources: ["buckets", "gitrepositories", "helmrepositories", "ocirepositories"]' "$rendered"
rg -Fq 'kind: ClusterRole' "$rendered"
rg -Fq 'kind: ClusterRoleBinding' "$rendered"
rg -Fq 'name: envpilot-control-plane-same-cluster-project-executor-release-manager' "$rendered"
rg -Fq 'resources: ["clusterroles", "clusterrolebindings"]' "$rendered"
rg -Fq 'resources: ["roles", "rolebindings"]' "$rendered"
rg -Fq 'resources: ["pods", "services", "endpoints", "events", "configmaps", "resourcequotas", "limitranges", "persistentvolumeclaims", "serviceaccounts"]' "$rendered"
rg -Fq 'resources: ["deployments", "daemonsets", "replicasets", "statefulsets"]' "$rendered"
rg -Fq 'resources: ["jobs", "cronjobs"]' "$rendered"
rg -Fq 'resources: ["ingresses", "networkpolicies"]' "$rendered"
rg -Fq 'resources: ["kustomizations"]' "$rendered"
rg -Fq 'resources: ["helmreleases"]' "$rendered"
rg -Fq 'resources: ["gitrepositories", "helmrepositories", "ocirepositories", "buckets"]' "$rendered"
rg -Fq 'resources: ["ingressclasses"]' "$rendered"
rg -Fq 'resources: ["customresourcedefinitions"]' "$rendered"
rg -Fq 'resources: ["storageclasses"]' "$rendered"
! rg -q 'resources: \["\*"\]|verbs: \["\*"\]' "$rendered"

# A project executor must never silently fall back to an anonymous OCI pull.
# The Registry Secret name is configuration only; its contents stay write-only.
if helm template missing-registry "$chart_dir" \
  --set 'postgres.tls.enabled=false' \
  --set 'global.envpilot.firstStartRegistration.mode=managed' \
  --set 'global.envpilot.firstStartRegistration.project.id=envpilot' \
  --set 'global.envpilot.firstStartRegistration.project.productId=generic' \
  --set 'global.envpilot.firstStartRegistration.agent.id=envpilot-agent' \
  --set 'global.envpilot.firstStartRegistration.runner.id=envpilot-runner' \
  --set 'global.envpilot.firstStartRegistration.runner.deploymentMode=helm' \
  --set 'global.envpilot.firstStartRegistration.cluster.id=bethunder-local' \
  --set 'global.envpilot.sameClusterProjectExecutors.enabled=true' \
  --set 'global.envpilot.sameClusterProjectExecutors.namespace=envpilot-executors' >/dev/null 2>&1; then
  echo 'expected signed OCI registry Secret requirement to fail rendering' >&2
  exit 1
fi

helm template project-agent "$chart_dir/../envpilot-agent" \
  --set 'global.envpilot.firstStartRegistration.mode=managed' \
  --set 'global.envpilot.firstStartRegistration.project.id=singleton' \
  --set 'managedSameCluster.enabled=true' \
  --set 'bootstrap.projectId=project-cms' \
  --set 'agent.id=project-cms-agent' \
  --set 'cluster.id=bethunder-local' \
  --set 'controlPlane.existingSecret=project-cms-agent-bootstrap' \
  --set 'controlPlane.allowInsecure=true' \
  --set 'rbac.discovery.scope=namespace' \
  --set 'rbac.discovery.namespaces[0]=envpilot-executors' \
  --set 'installValidation.enabled=false' >"$agent_rendered"
rg -Fq 'value: "project-cms"' "$agent_rendered"
rg -Fq 'value: "project-cms-agent"' "$agent_rendered"
! rg -Fq 'value: "singleton"' "$agent_rendered"
! rg -q 'kind: ClusterRole|kind: ClusterRoleBinding' "$agent_rendered"
rg -Fq 'kind: PersistentVolumeClaim' "$agent_rendered"
rg -Fq 'name: ENVPILOT_ALLOW_INSECURE_CONTROL_PLANE' "$agent_rendered"

helm template project-runner "$chart_dir/../envpilot-runner" \
  --set 'global.envpilot.firstStartRegistration.mode=managed' \
  --set 'global.envpilot.firstStartRegistration.project.id=singleton' \
  --set 'managedSameCluster.enabled=true' \
  --set 'project.id=project-cms' \
  --set 'project.runnerId=project-cms-runner' \
  --set 'project.clusterId=bethunder-local' \
  --set 'project.namespace=envpilot-executors' \
  --set 'controlPlane.existingSecret=project-cms-runner-bootstrap' \
  --set 'rbac.discovery.scope=namespace' \
  --set 'rbac.discovery.namespace=envpilot-executors' \
  --set 'rbac.featureEnvWriter.mode=preconfiguredNamespaces' \
  --set 'rbac.featureEnvWriter.namespaces[0]=envpilot-executors' >"$runner_rendered"
rg -Fq 'value: "project-cms"' "$runner_rendered"
rg -Fq 'value: "project-cms-runner"' "$runner_rendered"
! rg -Fq 'value: "singleton"' "$runner_rendered"
! rg -q 'kind: ClusterRole|kind: ClusterRoleBinding' "$runner_rendered"
rg -Fq 'kind: PersistentVolumeClaim' "$runner_rendered"
