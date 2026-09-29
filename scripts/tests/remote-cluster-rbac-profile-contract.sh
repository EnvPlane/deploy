#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
renderer="$root/scripts/render-remote-cluster-rbac-profile.sh"
rendered="$(mktemp "${TMPDIR:-/tmp}/envplane-remote-rbac.XXXXXX")"
trap 'rm -f "$rendered"' EXIT

bash "$renderer" --cluster-id customer-west --runtime-namespace envplane-system --managed-namespace base-api >"$rendered"

grep -Fq 'name: envplane-remote-cluster-customer-west-cluster-capability-reader' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-namespace-inventory-reader' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-feature-env-writer-parent' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-runtime-manager' "$rendered"
grep -Fq 'namespace: base-api' "$rendered"
if grep -Eq 'resources: \["\*"\]|verbs: \["\*"\]' "$rendered"; then
  echo 'remote cluster profile must not grant wildcard permissions' >&2
  exit 1
fi
if grep -A8 -F 'resources: ["clusterroles"]' "$rendered" | grep -Fq '"create"'; then
  echo 'remote cluster profile must not create release-named ClusterRoles' >&2
  exit 1
fi
if bash "$renderer" --cluster-id 'BAD_Name' >/dev/null 2>&1; then
  echo 'renderer accepted an invalid cluster ID' >&2
  exit 1
fi

chart="$root/deploy/helm/envplane-agent"
agent_rendered="$(mktemp "${TMPDIR:-/tmp}/envplane-remote-agent-rbac.XXXXXX")"
trap 'rm -f "$rendered" "$agent_rendered"' EXIT
helm template remote-agent "$chart" --namespace envplane-system \
  --set rbac.discovery.scope=namespace \
  --set rbac.discovery.clusterCapabilityRead=true \
  --set 'rbac.discovery.existingClusterRoles[0]=envplane-remote-cluster-customer-west-cluster-capability-reader' \
  --set 'rbac.discovery.existingClusterRoles[1]=envplane-remote-cluster-customer-west-namespace-inventory-reader' \
  --set 'rbac.discovery.namespaces[0]=base-api' \
  --set managedRemote.enabled=true \
  --set managedRemote.remoteClusterId=customer-west \
  --set managedRemote.projectId=platform \
  --set managedRemote.authRevision=generation-1 \
  --set managedRemote.compatibilityPin=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --set managedRemote.generation=1 \
  --set 'managedRemote.targetNamespaces[0]=base-api' \
  --set controlPlane.endpointMode=remote \
  --set controlPlane.url=https://control.example.test \
  --set controlPlane.existingSecret=agent-bootstrap >"$agent_rendered"
if grep -A3 -F 'kind: ClusterRole' "$agent_rendered" | grep -Fq 'remote-agent-envplane-agent-cluster-capability-reader'; then
  echo 'managed remote Agent must bind the fixed capability role instead of rendering a release-named ClusterRole' >&2
  exit 1
fi
grep -Fq 'name: envplane-remote-cluster-customer-west-cluster-capability-reader' "$agent_rendered"

echo 'remote cluster RBAC profile contract is valid'
