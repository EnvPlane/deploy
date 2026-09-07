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
  --set 'rbac.sameClusterProjectExecutors.namespace=envplane-executors' \
  --set 'rbac.sameClusterProjectExecutors.admissionPolicy.enabled=true' >"$rendered"

grep -Fq 'name: ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_ENABLED' "$rendered"
grep -Fq 'value: "true"' "$rendered"
grep -Fq 'name: ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_NAMESPACE' "$rendered"
grep -Fq 'value: "envplane-executors"' "$rendered"
grep -Fq 'name: ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_IMAGE_PULL_SECRET' "$rendered"
grep -Fq 'value: "envplane-ghcr"' "$rendered"
grep -Fq 'name: ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_DISCOVERY_NAMESPACES' "$rendered"
grep -Fq 'value: "envplane-e2e-base,envplane-shared"' "$rendered"
grep -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_RETIREMENT_ENABLED' "$rendered"
grep -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_NAMESPACE' "$rendered"
grep -Fq 'fieldPath: metadata.namespace' "$rendered"
grep -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_AGENT_DEPLOYMENT' "$rendered"
grep -Fq 'value: "envplane-agent"' "$rendered"
grep -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNNER_DEPLOYMENT' "$rendered"
grep -Fq 'value: "envplane-runner"' "$rendered"
grep -Fq 'name: ENVPLANE_SAME_CLUSTER_BOOTSTRAP_RUNTIME_STATE_CONFIG_MAP' "$rendered"
grep -Fq 'value: "envplane-bootstrap-runtime-lifecycle"' "$rendered"
grep -Fq 'name: envplane-control-plane-bootstrap-runtime-retirement' "$rendered"
grep -Fq 'resourceNames: ["envplane-bootstrap-runtime-lifecycle"]' "$rendered"
grep -Fq 'resourceNames: ["envplane-agent", "envplane-runner"]' "$rendered"
! grep -Fq 'envplane-control-plane-platform-dependency-status-reader---' "$rendered"
grep -Fq 'name: HOME' "$rendered"
grep -Fq 'value: /tmp/envplane-home' "$rendered"
grep -Fq 'name: XDG_CACHE_HOME' "$rendered"
grep -Fq 'value: /tmp/envplane-home/cache' "$rendered"
grep -Fq 'name: HELM_REGISTRY_CONFIG' "$rendered"
grep -Fq 'value: /etc/envplane/helm-registry/config.json' "$rendered"
grep -Fq 'name: executor-registry-config' "$rendered"
grep -Fq 'secretName: "envplane-ghcr"' "$rendered"
grep -Fq 'key: .dockerconfigjson' "$rendered"
# The registry Secret remains operator-managed. The chart can reference its
# name, but must never render a credential-bearing Secret for it.
! awk '
  /kind: Secret/ {
    if (getline && $0 == "metadata:" && getline && $0 == "  name: \\\"envplane-ghcr\\\"") {
      found = 1
    }
  }
  END { exit found ? 0 : 1 }
' "$rendered"
! grep -Eq 'dockerconfigjson:' "$rendered"
grep -Fq 'name: envplane-control-plane-same-cluster-project-executors' "$rendered"
grep -Fq 'namespace: "envplane-executors"' "$rendered"
# Namespace lifecycle is owned by the umbrella chart; this standalone child
# contract validates only the namespaced executor permissions it can render.
# Kubernetes anti-escalation requires the control plane to hold the exact
# namespaced rules it delegates to project-owned Agent and Runner releases.
# The Runner writer contract remains limited to the executor namespace.
grep -Fq 'resources: ["configmaps", "endpoints", "events", "limitranges", "resourcequotas", "services"]' "$rendered"
grep -Fq 'resources: ["configmaps", "events", "limitranges", "resourcequotas", "services"]' "$rendered"
grep -Fq 'resources: ["statefulsets"]' "$rendered"
grep -Fq 'resources: ["cronjobs", "jobs"]' "$rendered"
grep -Fq 'resources: ["ingresses"]' "$rendered"
grep -Fq 'verbs: ["create", "update", "patch", "delete"]' "$rendered"
grep -Fq 'resources: ["buckets", "gitrepositories", "helmrepositories", "ocirepositories"]' "$rendered"
grep -Fq 'kind: ClusterRole' "$rendered"
grep -Fq 'kind: ClusterRoleBinding' "$rendered"
grep -Fq 'name: envplane-control-plane-same-cluster-project-executor-release-manager' "$rendered"
grep -Fq 'resources: ["clusterroles", "clusterrolebindings"]' "$rendered"
grep -Fq 'resources: ["roles", "rolebindings"]' "$rendered"
grep -Fq 'kind: ClusterPolicy' "$rendered"
grep -Fq 'name: envplane-control-plane-same-cluster-rbac-guard' "$rendered"
grep -Fq 'validationFailureAction: Enforce' "$rendered"
grep -Fq 'deny-cluster-admin-bindings' "$rendered"
grep -Fq 'Bindings to cluster-admin are not permitted.' "$rendered"
grep -Fq 'restrict-control-plane-cluster-role-bindings' "$rendered"
grep -Fq 'restrict-control-plane-cluster-roles' "$rendered"
grep -Fq 'operator: NotIn' "$rendered"
grep -Fq -- '- envplane-control-plane-same-cluster-project-executor-release-manager' "$rendered"
# The release-manager ClusterRole retains delegated writes only because the
# rendered admission policy enforces the explicit role allowlist.
grep -Fq 'value: ClusterRole' "$rendered"
grep -Fq 'resources: ["pods", "services", "endpoints", "events", "configmaps", "resourcequotas", "limitranges", "persistentvolumeclaims", "serviceaccounts"]' "$rendered"
grep -Fq 'resources: ["deployments", "daemonsets", "replicasets", "statefulsets"]' "$rendered"
grep -Fq 'resources: ["jobs", "cronjobs"]' "$rendered"
grep -Fq 'resources: ["ingresses", "networkpolicies"]' "$rendered"
grep -Fq 'resources: ["horizontalpodautoscalers"]' "$rendered"
grep -Fq 'resources: ["poddisruptionbudgets"]' "$rendered"
grep -Fq 'resources: ["kustomizations"]' "$rendered"
grep -Fq 'verbs: ["get", "list", "watch", "create", "update", "patch"]' "$rendered"
grep -Fq 'resources: ["helmreleases"]' "$rendered"
grep -Fq 'resources: ["gitrepositories", "helmrepositories", "ocirepositories", "buckets"]' "$rendered"
grep -Fq 'resources: ["gitrepositories"]' "$rendered"
grep -Fq 'resources: ["namespaces"]' "$rendered"
grep -Fq 'verbs: ["get", "list", "watch", "create"]' "$rendered"
grep -Fq 'resources: ["ingressclasses"]' "$rendered"
grep -Fq 'resources: ["customresourcedefinitions"]' "$rendered"
grep -Fq 'resources: ["storageclasses"]' "$rendered"
! grep -Eq 'resources: \["\*"\]|verbs: \["\*"\]' "$rendered"

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
! grep -Eq 'ENVPLANE_SAME_CLUSTER_PROJECT_EXECUTORS_IMAGE_PULL_SECRET|executor-registry-config|HELM_REGISTRY_CONFIG' "$public_rendered"
# Zero-setup cannot require a Kyverno CRD. The admission guard remains an
# explicit hardening option, covered by the private-registry render above.
! grep -Fq 'kind: ClusterPolicy' "$public_rendered"

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
grep -Fq 'value: "project-cms"' "$agent_rendered"
grep -Fq 'value: "project-cms-agent"' "$agent_rendered"
! grep -Fq 'value: "singleton"' "$agent_rendered"
! grep -Eq 'kind: ClusterRole|kind: ClusterRoleBinding' "$agent_rendered"
grep -Fq 'kind: PersistentVolumeClaim' "$agent_rendered"
grep -Fq 'name: ENVPLANE_ALLOW_INSECURE_CONTROL_PLANE' "$agent_rendered"
! grep -Fq 'envplane.io/bootstrap-runtime: "true"' "$agent_rendered"

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
grep -Fq 'value: "project-cms"' "$runner_rendered"
grep -Fq 'value: "project-cms-runner"' "$runner_rendered"
! grep -Fq 'value: "singleton"' "$runner_rendered"
! grep -Eq 'kind: ClusterRole|kind: ClusterRoleBinding' "$runner_rendered"
grep -Fq 'kind: PersistentVolumeClaim' "$runner_rendered"
! grep -Fq 'envplane.io/bootstrap-runtime: "true"' "$runner_rendered"
