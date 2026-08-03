#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/scripts/published-remote-cluster-two-cluster-e2e.sh"
bash -n "$script"
for required in 'helm upgrade --install' '/api/v1/remote-clusters' 'control-plane-preflight' 'resource-scan/start' 'helm-direct/preflight' 'creates a real full environment through the UI' 'unreachable.invalid' '/credentials/rotate' '/rotate' '/repair'; do grep -Fq "$required" "$script"; done
if grep -Eq 'helm[[:space:]]+upgrade.*envpilot-(agent|runner)|minikube[[:space:]]+start' "$script"; then echo 'two-cluster E2E must use the umbrella and RemoteCluster reconciler only' >&2; exit 1; fi
echo 'published two-cluster RemoteCluster contract is valid'
