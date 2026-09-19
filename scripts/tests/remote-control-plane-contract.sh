#!/usr/bin/env bash
# Fast contract guard for the two-context E2E harness. The full E2E receives
# already provisioned clusters and a stable remote endpoint via environment.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/scripts/minikube-environment-e2e.sh"

bash -n "$script"
grep -Fq 'ENVPLANE_E2E_REMOTE_CONTROL_PLANE_URL' "$script"
grep -Fq 'controlPlane.endpointMode=remote' "$script"
grep -Fq 'ENVPLANE_E2E_CHART_REF' "$script"
grep -Fq 'ENVPLANE_E2E_AGENT_CHART_VERSION' "$script"
grep -Fq 'ENVPLANE_E2E_RUNNER_CHART_VERSION' "$script"
grep -Fq 'ENVPLANE_E2E_AGENT_IMAGE_TAG' "$script"
grep -Fq 'ENVPLANE_E2E_RUNNER_IMAGE_TAG' "$script"
grep -Fq 'assert_remote_heartbeats_remain_fresh' "$script"
grep -Fq 'verify_remote_runtime_after_installer_exit' "$script"
grep -Fq 'complete_bootstrap' "$script"
grep -Fq 'assert_deploy_ready' "$script"
grep -Fq 'stable https:// endpoint' "$script"

if grep -Fq 'minikube-agent-access.sh" start' "$script" || grep -Fq 'host.minikube.internal:' "$script" || grep -Fq 'minikube -p' "$script" || grep -Fq 'image.tag=local' "$script" || grep -Fq 'rollout restart' "$script"; then
	echo "remote E2E script must not start a local gateway, special-case minikube, use local artifacts, or require a manual rollout restart" >&2
  exit 1
fi

rendered="$(mktemp "${TMPDIR:-/tmp}/envplane-remote-contract.XXXXXX")"
trap 'rm -f "$rendered"' EXIT
helm template envplane "$root/deploy/helm/envplane" --namespace envplane \
  --set envplane-control-plane.remoteControlPlane.url=https://api.remote.example \
  --set envplane-control-plane.remoteControlPlane.caSecret=remote-control-plane-ca \
  --set envplane-control-plane.remoteControlPlane.clusterID=control-cluster > "$rendered"
grep -Fq 'name: ENVPLANE_MANAGEMENT_ENDPOINT_BOOTSTRAP_URL' "$rendered"
grep -Fq 'value: "https://api.remote.example"' "$rendered"
grep -Fq 'name: ENVPLANE_MANAGEMENT_ENDPOINT_BOOTSTRAP_CA_SECRET' "$rendered"
grep -Fq 'name: ENVPLANE_CONTROL_PLANE_CLUSTER_ID' "$rendered"

echo "remote control-plane E2E contract is valid"
