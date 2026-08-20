#!/usr/bin/env bash
# Exercise the same generated agent-install command against a second Kubernetes
# context. The command is intentionally supplied by the caller (copy it from
# the wizard) so the test never substitutes an unrendered local-chart command.
# The command must use a stable remote endpoint; this helper never opens a
# tunnel or port-forward.
#
# Usage:
#   ENVPLANE_AGENT_HELM_COMMAND='kubectl run ... && helm upgrade ...' \
#     ./scripts/minikube-agent-e2e.sh <target-profile>
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_profile="${1:-${ENVPLANE_AGENT_TARGET_MINIKUBE_PROFILE:-}}"
command_to_test="${ENVPLANE_AGENT_HELM_COMMAND:-}"
agent_namespace="${ENVPLANE_AGENT_E2E_NAMESPACE:-envplane-system}"
agent_deployment="${ENVPLANE_AGENT_E2E_DEPLOYMENT:-envplane-agent}"

[[ -n "$target_profile" ]] || { echo "ERROR: target Kubernetes context is required" >&2; exit 1; }
[[ -n "$command_to_test" ]] || { echo "ERROR: set ENVPLANE_AGENT_HELM_COMMAND to the wizard's displayed Helm command" >&2; exit 1; }
if [[ "$command_to_test" == *"host.minikube.internal"* || "$command_to_test" == *"envplane.local"* ]]; then
  echo "ERROR: generated command uses a host-local endpoint. Configure the control plane with a stable remote target-pod-reachable endpoint first." >&2
  exit 1
fi

previous_context="$(kubectl config current-context 2>/dev/null || true)"
cleanup() {
  if [[ -n "$previous_context" ]]; then
    kubectl config use-context "$previous_context" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

kubectl config use-context "$target_profile" >/dev/null
eval "$command_to_test"
kubectl -n "$agent_namespace" rollout status "deployment/$agent_deployment" --timeout=180s
kubectl -n "$agent_namespace" get "deployment/$agent_deployment"
