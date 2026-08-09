#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(mktemp)"
agent_rendered="$(mktemp)"
runner_rendered="$(mktemp)"
trap 'rm -f "$rendered" "$agent_rendered" "$runner_rendered"' EXIT

helm template envpilot "$chart_dir" \
  --set 'global.envpilot.firstStartRegistration.mode=managed' \
  --set 'global.envpilot.firstStartRegistration.project.id=envpilot' \
  --set 'global.envpilot.firstStartRegistration.project.productId=generic' \
  --set 'global.envpilot.firstStartRegistration.agent.id=envpilot-agent' \
  --set 'global.envpilot.firstStartRegistration.runner.id=envpilot-runner' \
  --set 'global.envpilot.firstStartRegistration.runner.deploymentMode=helm' \
  --set 'global.envpilot.firstStartRegistration.cluster.id=bethunder-local' \
  --set 'global.envpilot.sameClusterProjectExecutors.enabled=true' \
  --set 'global.envpilot.sameClusterProjectExecutors.namespace=envpilot-executors' \
  --set 'rbac.sameClusterProjectExecutors.enabled=true' \
  --set 'rbac.sameClusterProjectExecutors.namespace=envpilot-executors' >"$rendered"

rg -Fq 'name: ENVPILOT_SAME_CLUSTER_PROJECT_EXECUTORS_ENABLED' "$rendered"
rg -Fq 'value: "true"' "$rendered"
rg -Fq 'name: ENVPILOT_SAME_CLUSTER_PROJECT_EXECUTORS_NAMESPACE' "$rendered"
rg -Fq 'value: "envpilot-executors"' "$rendered"
rg -Fq 'name: envpilot-control-plane-same-cluster-project-executors' "$rendered"
rg -Fq 'namespace: "envpilot-executors"' "$rendered"
! rg -q 'kind: ClusterRole|kind: ClusterRoleBinding' "$rendered"
! rg -q 'resources: \["\*"\]|verbs: \["\*"\]' "$rendered"

helm template project-agent "$chart_dir/../envpilot-agent" \
  --set 'global.envpilot.firstStartRegistration.mode=managed' \
  --set 'global.envpilot.firstStartRegistration.project.id=singleton' \
  --set 'managedSameCluster.enabled=true' \
  --set 'bootstrap.projectId=project-cms' \
  --set 'agent.id=project-cms-agent' \
  --set 'cluster.id=bethunder-local' \
  --set 'controlPlane.existingSecret=project-cms-agent-bootstrap' \
  --set 'rbac.discovery.scope=namespace' \
  --set 'rbac.discovery.namespaces[0]=envpilot-executors' \
  --set 'agent.authPersistence.createClaim=false' \
  --set 'installValidation.enabled=false' >"$agent_rendered"
rg -Fq 'value: "project-cms"' "$agent_rendered"
rg -Fq 'value: "project-cms-agent"' "$agent_rendered"
! rg -Fq 'value: "singleton"' "$agent_rendered"
! rg -q 'kind: ClusterRole|kind: ClusterRoleBinding' "$agent_rendered"

helm template project-runner "$chart_dir/../envpilot-runner" \
  --set 'global.envpilot.firstStartRegistration.mode=managed' \
  --set 'global.envpilot.firstStartRegistration.project.id=singleton' \
  --set 'managedSameCluster.enabled=true' \
  --set 'project.id=project-cms' \
  --set 'project.runnerId=project-cms-runner' \
  --set 'project.clusterId=bethunder-local' \
  --set 'project.namespace=envpilot-executors' \
  --set 'controlPlane.existingSecret=project-cms-runner-bootstrap' \
  --set 'controlPlane.authPersistence.createClaim=false' \
  --set 'rbac.discovery.scope=namespace' \
  --set 'rbac.discovery.namespace=envpilot-executors' \
  --set 'rbac.featureEnvWriter.mode=preconfiguredNamespaces' \
  --set 'rbac.featureEnvWriter.namespaces[0]=envpilot-executors' >"$runner_rendered"
rg -Fq 'value: "project-cms"' "$runner_rendered"
rg -Fq 'value: "project-cms-runner"' "$runner_rendered"
! rg -Fq 'value: "singleton"' "$runner_rendered"
! rg -q 'kind: ClusterRole|kind: ClusterRoleBinding' "$runner_rendered"
