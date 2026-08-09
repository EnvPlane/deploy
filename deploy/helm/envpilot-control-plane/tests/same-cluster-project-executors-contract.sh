#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

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
