#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(mktemp)"
agent_rendered="$(mktemp)"
runner_rendered="$(mktemp)"
trap 'rm -f "$rendered" "$agent_rendered" "$runner_rendered"' EXIT

helm template envplane "$chart_dir" \
  --set 'postgres.tls.enabled=false' \
  --set 'global.envplane.firstStartRegistration.mode=managed' \
  --set 'global.envplane.firstStartRegistration.project.id=envplane' \
  --set 'global.envplane.firstStartRegistration.project.productId=generic' \
  --set 'global.envplane.firstStartRegistration.agent.id=envplane-agent' \
  --set 'global.envplane.firstStartRegistration.runner.id=envplane-runner' \
  --set 'global.envplane.firstStartRegistration.runner.deploymentMode=helm' \
  --set 'global.envplane.firstStartRegistration.cluster.id=bethunder-local' \
  --set 'global.envplane.sameClusterProjectExecutors.enabled=true' \
  --set 'global.envplane.sameClusterProjectExecutors.namespace=envplane-executors' \
  --set 'global.envplane.sameClusterProjectExecutors.discovery.namespaces[0]=envplane-e2e-base' \
  --set 'global.envplane.sameClusterProjectExecutors.discovery.namespaces[1]=envplane-shared' \
  --set 'global.envplane.sameClusterProjectExecutors.registry.existingSecret=envplane-ghcr' \
  --set 'global.envplane.sameClusterProjectExecutors.registry.imagePullSecret=envplane-ghcr' \
  --set 'global.envplane.sameClusterProjectExecutors.bootstrapRuntime.retirementEnabled=true' \
  --set 'global.envplane.sameClusterProjectExecutors.bootstrapRuntime.agentDeployment=envplane-agent' \
  --set 'global.envplane.sameClusterProjectExecutors.bootstrapRuntime.runnerDeployment=envplane-runner' \
  --set 'global.envplane.sameClusterProjectExecutors.bootstrapRuntime.stateConfigMap=envplane-bootstrap-runtime-lifecycle' \
  --set 'rbac.sameClusterProjectExecutors.enabled=true' \
  --set 'rbac.sameClusterProjectExecutors.namespace=envplane-executors' >"$rendered"

rg -Fq 'name: ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_ENABLED' "$rendered"
rg -Fq 'value: "true"' "$rendered"
rg -Fq 'name: ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_NAMESPACE' "$rendered"
rg -Fq 'value: "envplane-executors"' "$rendered"
rg -Fq 'name: ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_IMAGE_PULL_SECRET' "$rendered"
rg -Fq 'value: "envplane-ghcr"' "$rendered"
rg -Fq 'name: ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_DISCOVERY_NAMESPACES' "$rendered"
rg -Fq 'value: "envplane-e2e-base,envplane-shared"' "$rendered"
rg -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_RETIREMENT_ENABLED' "$rendered"
rg -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_NAMESPACE' "$rendered"
rg -Fq 'fieldPath: metadata.namespace' "$rendered"
rg -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_AGENT_DEPLOYMENT' "$rendered"
rg -Fq 'value: "envplane-agent"' "$rendered"
rg -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNNER_DEPLOYMENT' "$rendered"
rg -Fq 'value: "envplane-runner"' "$rendered"
rg -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_STATE_CONFIG_MAP' "$rendered"
rg -Fq 'value: "envplane-bootstrap-runtime-lifecycle"' "$rendered"
rg -Fq 'name: envplane-control-plane-bootstrap-runtime-retirement' "$rendered"
rg -Fq 'resourceNames: ["envplane-bootstrap-runtime-lifecycle"]' "$rendered"
rg -Fq 'resourceNames: ["envplane-agent", "envplane-runner"]' "$rendered"
! rg -Fq 'envplane-control-plane-platform-dependency-status-reader---' "$rendered"
rg -Fq 'name: HOME' "$rendered"
rg -Fq 'value: /tmp/envplane-home' "$rendered"
rg -Fq 'name: XDG_CACHE_HOME' "$rendered"
rg -Fq 'value: /tmp/envplane-home/cache' "$rendered"
rg -Fq 'name: HELM_REGISTRY_CONFIG' "$rendered"
rg -Fq 'value: /etc/envplane/helm-registry/config.json' "$rendered"
rg -Fq 'name: executor-registry-config' "$rendered"
rg -Fq 'secretName: "envplane-ghcr"' "$rendered"
rg -Fq 'key: .dockerconfigjson' "$rendered"
# The registry Secret remains operator-managed. The chart can reference its
# name, but must never render a credential-bearing Secret for it.
! rg -Uq 'kind: Secret\nmetadata:\n  name: "envplane-ghcr"' "$rendered"
! rg -q 'dockerconfigjson:' "$rendered"
rg -Fq 'name: envplane-control-plane-same-cluster-project-executors' "$rendered"
rg -Fq 'namespace: "envplane-executors"' "$rendered"
# Namespace lifecycle is owned by the umbrella chart; this standalone child
# contract validates only the namespaced executor permissions it can render.
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
rg -Fq 'name: envplane-control-plane-same-cluster-project-executor-release-manager' "$rendered"
rg -Fq 'resources: ["clusterroles", "clusterrolebindings"]' "$rendered"
rg -Fq 'resources: ["roles", "rolebindings"]' "$rendered"
rg -Fq 'resources: ["pods", "services", "endpoints", "events", "configmaps", "resourcequotas", "limitranges", "persistentvolumeclaims", "serviceaccounts"]' "$rendered"
rg -Fq 'resources: ["deployments", "daemonsets", "replicasets", "statefulsets"]' "$rendered"
rg -Fq 'resources: ["jobs", "cronjobs"]' "$rendered"
rg -Fq 'resources: ["ingresses", "networkpolicies"]' "$rendered"
rg -Fq 'resources: ["horizontalpodautoscalers"]' "$rendered"
rg -Fq 'resources: ["poddisruptionbudgets"]' "$rendered"
rg -Fq 'resources: ["kustomizations"]' "$rendered"
rg -Fq 'resources: ["helmreleases"]' "$rendered"
rg -Fq 'resources: ["gitrepositories", "helmrepositories", "ocirepositories", "buckets"]' "$rendered"
rg -Fq 'resources: ["namespaces"]' "$rendered"
rg -Fq 'verbs: ["get", "list", "watch", "create"]' "$rendered"
rg -Fq 'resources: ["ingressclasses"]' "$rendered"
rg -Fq 'resources: ["customresourcedefinitions"]' "$rendered"
rg -Fq 'resources: ["storageclasses"]' "$rendered"
! rg -q 'resources: \["\*"\]|verbs: \["\*"\]' "$rendered"

# Public EnvPlane OCI artifacts are the default: a project executor must render
# without a registry Secret in either namespace. Private registry credentials
# remain an explicit optional override covered by the render above.
public_rendered="$(mktemp)"
trap 'rm -f "$rendered" "$agent_rendered" "$runner_rendered" "$public_rendered"' EXIT
helm template public-oci "$chart_dir" \
  --set 'postgres.tls.enabled=false' \
  --set 'global.envplane.firstStartRegistration.mode=managed' \
  --set 'global.envplane.firstStartRegistration.project.id=envplane' \
  --set 'global.envplane.firstStartRegistration.project.productId=generic' \
  --set 'global.envplane.firstStartRegistration.agent.id=envplane-agent' \
  --set 'global.envplane.firstStartRegistration.runner.id=envplane-runner' \
  --set 'global.envplane.firstStartRegistration.runner.deploymentMode=helm' \
  --set 'global.envplane.firstStartRegistration.cluster.id=bethunder-local' \
  --set 'global.envplane.sameClusterProjectExecutors.enabled=true' \
  --set 'global.envplane.sameClusterProjectExecutors.namespace=envplane-executors' \
  >"$public_rendered"
! rg -q 'ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_IMAGE_PULL_SECRET|executor-registry-config|HELM_REGISTRY_CONFIG' "$public_rendered"

helm template project-agent "$chart_dir/../envplane-agent" \
  --set 'global.envplane.firstStartRegistration.mode=managed' \
  --set 'global.envplane.firstStartRegistration.project.id=singleton' \
  --set 'managedSameCluster.enabled=true' \
  --set 'bootstrap.projectId=project-cms' \
  --set 'agent.id=project-cms-agent' \
  --set 'cluster.id=bethunder-local' \
  --set 'controlPlane.existingSecret=project-cms-agent-bootstrap' \
  --set 'controlPlane.allowInsecure=true' \
  --set 'rbac.discovery.scope=namespace' \
  --set 'rbac.discovery.namespaces[0]=envplane-executors' \
  --set 'installValidation.enabled=false' >"$agent_rendered"
rg -Fq 'value: "project-cms"' "$agent_rendered"
rg -Fq 'value: "project-cms-agent"' "$agent_rendered"
! rg -Fq 'value: "singleton"' "$agent_rendered"
! rg -q 'kind: ClusterRole|kind: ClusterRoleBinding' "$agent_rendered"
rg -Fq 'kind: PersistentVolumeClaim' "$agent_rendered"
rg -Fq 'name: ENVPLANE_ALLOW_INSECURE_CONTROL_PLANE' "$agent_rendered"
! rg -Fq 'envplane.io/bootstrap-runtime: "true"' "$agent_rendered"

helm template project-runner "$chart_dir/../envplane-runner" \
  --set 'global.envplane.firstStartRegistration.mode=managed' \
  --set 'global.envplane.firstStartRegistration.project.id=singleton' \
  --set 'managedSameCluster.enabled=true' \
  --set 'project.id=project-cms' \
  --set 'project.runnerId=project-cms-runner' \
  --set 'project.clusterId=bethunder-local' \
  --set 'project.namespace=envplane-executors' \
  --set 'controlPlane.existingSecret=project-cms-runner-bootstrap' \
  --set 'rbac.discovery.scope=namespace' \
  --set 'rbac.discovery.namespace=envplane-executors' \
  --set 'rbac.featureEnvWriter.mode=preconfiguredNamespaces' \
  --set 'rbac.featureEnvWriter.namespaces[0]=envplane-executors' >"$runner_rendered"
rg -Fq 'value: "project-cms"' "$runner_rendered"
rg -Fq 'value: "project-cms-runner"' "$runner_rendered"
! rg -Fq 'value: "singleton"' "$runner_rendered"
! rg -q 'kind: ClusterRole|kind: ClusterRoleBinding' "$runner_rendered"
rg -Fq 'kind: PersistentVolumeClaim' "$runner_rendered"
! rg -Fq 'envplane.io/bootstrap-runtime: "true"' "$runner_rendered"
