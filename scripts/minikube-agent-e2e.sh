#!/usr/bin/env bash
# Exercise the same generated agent-install command against a second minikube
# profile. The command is intentionally supplied by the caller (copy it from
# the wizard) so the test never substitutes an unrendered local-chart command.
#
# Usage:
#   ENVPILOT_AGENT_HELM_COMMAND='kubectl run ... && helm upgrade ...' \
#     ./scripts/minikube-agent-e2e.sh <target-profile>
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_profile="${1:-${ENVPILOT_AGENT_TARGET_MINIKUBE_PROFILE:-}}"
command_to_test="${ENVPILOT_AGENT_HELM_COMMAND:-}"
agent_namespace="${ENVPILOT_AGENT_E2E_NAMESPACE:-envpilot-system}"
agent_deployment="${ENVPILOT_AGENT_E2E_DEPLOYMENT:-envpilot-agent}"

[[ -n "$target_profile" ]] || { echo "ERROR: target minikube profile is required" >&2; exit 1; }
[[ -n "$command_to_test" ]] || { echo "ERROR: set ENVPILOT_AGENT_HELM_COMMAND to the wizard's displayed Helm command" >&2; exit 1; }

"$DEPLOY_ROOT/scripts/minikube-agent-access.sh" start "$target_profile"
previous_context="$(kubectl config current-context 2>/dev/null || true)"
cleanup() {
  if [[ -n "$previous_context" ]]; then
    kubectl config use-context "$previous_context" >/dev/null 2>&1 || true
  fi
  "$DEPLOY_ROOT/scripts/minikube-agent-access.sh" stop
}
trap cleanup EXIT

kubectl config use-context "$target_profile" >/dev/null
eval "$command_to_test"
kubectl -n "$agent_namespace" rollout status "deployment/$agent_deployment" --timeout=180s
kubectl -n "$agent_namespace" get "deployment/$agent_deployment"
