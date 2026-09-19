#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/scripts/published-remote-cluster-two-cluster-e2e.sh"
bash -n "$script"
for required in 'helm upgrade --install' 'envplane-remote-cluster-reconciler' 'POD_NAMESPACE or remoteClusterReconciler.leaderElection.namespace' '/api/v1/management-endpoint-profile' 'managementCopy' 'ENVPLANE_E2E_REMOTE_CONTROL_PLANE_CA_FILE' 'ENVPLANE_E2E_REMOTE_CONTROL_PLANE_ROTATED_CA_FILE' 'control-plane-preflight' 'assert_remote_runtime_after_installer_exit' 'resource-scan/start' 'helm-direct/preflight' 'creates a real full environment through the UI' 'does-not-resolve.invalid' 'private CA rotation did not advance target trust revision' '/repair'; do grep -Fq "$required" "$script"; done
if grep -Eq 'helm[[:space:]]+upgrade.*envplane-(agent|runner)|minikube[[:space:]]+start|kubectl[^\n]*port-forward' "$script"; then echo 'two-cluster E2E must use only the umbrella, stable external endpoints, and RemoteCluster reconciliation' >&2; exit 1; fi
echo 'published two-cluster RemoteCluster contract is valid'
