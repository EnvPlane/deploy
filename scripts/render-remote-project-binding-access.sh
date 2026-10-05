#!/usr/bin/env bash
# Supplemental exact-name access for a previously scoped remote installer.
# Render only: an operator reviews and applies the output. No credentials.
set -euo pipefail
cluster_id=""
project_id=""
runtime_namespace="envplane-system"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-id|--project-id|--runtime-namespace)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then echo "missing option value" >&2; exit 2; fi
      case "$1" in
        --cluster-id) cluster_id="$2" ;;
        --project-id) project_id="$2" ;;
        --runtime-namespace) runtime_namespace="$2" ;;
      esac
      shift 2 ;;
    *) echo "Usage: render-remote-project-binding-access.sh --cluster-id ID --project-id ID [--runtime-namespace NAME]" >&2; exit 2 ;;
  esac
done
for value in "$cluster_id" "$project_id" "$runtime_namespace"; do
  if [[ ! "$value" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ || ${#value} -gt 63 ]]; then echo "IDs and namespace must be DNS labels up to 63 characters" >&2; exit 2; fi
done
project_hash="$(printf '%s' "$project_id:agent" | shasum -a 256 | cut -c1-12)"
release="ep-agent-$project_hash"
prefix="envplane-remote-cluster-$cluster_id"
access_name="envplane-project-binding-access-$project_hash"
cat <<EOF
# Exact project Agent binding names; does not grant create, bind or escalate.
# Requires the existing reviewed remote installer profile and ownership checks.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $access_name-$cluster_id
rules:
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterrolebindings"]
    resourceNames:
EOF
for suffix in cluster-capability-reader namespace-metadata-reader namespace-inventory-reader; do
  identity="$release|$runtime_namespace|$prefix-$suffix"
  binding_hash="$(printf '%s' "$identity" | shasum -a 256 | cut -c1-10)"
  printf '      - %s-envplane-agent-capability-%s\n' "$release" "$binding_hash"
done
cat <<EOF
    verbs: ["get", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $access_name-$cluster_id
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $access_name-$cluster_id
subjects:
  - kind: ServiceAccount
    name: envplane-remote-cluster-$cluster_id
    namespace: $runtime_namespace
EOF
