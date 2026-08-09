#!/usr/bin/env bash
set -euo pipefail

# Published-artifact lifecycle E2E for API-managed remote clusters. Both
# Kubernetes clusters must already be provisioned. This harness never creates a cluster, opens a tunnel, or receives raw kubeconfig/bootstrap credentials.
: "${ENVPILOT_REMOTE_E2E_API_URL:?set management control-plane API URL}"
: "${ENVPILOT_REMOTE_E2E_CLUSTER_ID:?set the RemoteCluster ID}"
: "${ENVPILOT_REMOTE_E2E_REMOTE_CONTEXT:?set the target cluster kube context}"
: "${ENVPILOT_REMOTE_E2E_AGENT_RELEASE:?set target Agent release name}"
: "${ENVPILOT_REMOTE_E2E_AGENT_NAMESPACE:?set target Agent namespace}"
: "${ENVPILOT_REMOTE_E2E_RUNNER_RELEASE:?set target Runner release name}"
: "${ENVPILOT_REMOTE_E2E_RUNNER_NAMESPACE:?set target Runner namespace}"

api="${ENVPILOT_REMOTE_E2E_API_URL%/}"
cluster_id="$ENVPILOT_REMOTE_E2E_CLUSTER_ID"
auth_header=()
if [[ -n "${ENVPILOT_REMOTE_E2E_API_TOKEN:-}" ]]; then
  auth_header=(-H "Authorization: Bearer ${ENVPILOT_REMOTE_E2E_API_TOKEN}")
fi

request_action() {
  curl -fsS "${auth_header[@]}" -X POST "$api/api/v1/remote-clusters/$cluster_id/$1" > /dev/null
}

wait_for_phase() {
  local want="$1" body
  for _ in $(seq 1 90); do
    body="$(curl -fsS "${auth_header[@]}" "$api/api/v1/remote-clusters/$cluster_id" || true)"
    if [[ "$want" == "gone" ]]; then
      [[ -z "$body" ]] && return 0
    elif jq -e --arg phase "$want" '.status.phase == $phase and .status.observed_generation == .status.desired_generation' <<<"$body" >/dev/null 2>&1; then
      printf '%s\n' "$body"
      return 0
    fi
    sleep 2
  done
  echo "remote cluster $cluster_id did not reach $want" >&2
  return 1
}

# The management umbrella upgrade from N-1 to N is performed by the caller's
# published-artifact workflow. This harness proves that each explicit action
# binds Agent/Runner to the exact active immutable compatibility set.
request_action reconcile
n_minus_1="$(wait_for_phase healthy)"
jq -e '.status.installed_artifacts | length == 2 and all(.[]; .compatibility_fingerprint | startswith("sha256:"))' <<<"$n_minus_1" >/dev/null

request_action repair
n="$(wait_for_phase healthy)"
jq -e --argjson prior "$(jq '.status.observed_generation' <<<"$n_minus_1")" '.status.observed_generation > $prior' <<<"$n" >/dev/null

# A manually installed legacy release must remain unmanaged until the explicit
# audited API action. The fixture setup creates it with the same release/PVC
# names but without EnvPlane ownership values.
if [[ "${ENVPILOT_REMOTE_E2E_VERIFY_LEGACY_MIGRATION:-false}" == "true" ]]; then
  request_action migrate
  migrated="$(wait_for_phase healthy)"
  jq -e '.status.migration.completed_at != null and (.status.installed_artifacts | all(.[]; .compatibility_fingerprint != ""))' <<<"$migrated" >/dev/null
fi

# DELETE schedules controlled cleanup. It must uninstall only owned Agent and
# Runner releases while retaining their auth PVCs for an operator-approved
# rollback/recovery path.
curl -fsS "${auth_header[@]}" -X DELETE "$api/api/v1/remote-clusters/$cluster_id" > /dev/null
for _ in $(seq 1 90); do
  status="$(curl -sS -o /dev/null -w '%{http_code}' "${auth_header[@]}" "$api/api/v1/remote-clusters/$cluster_id")"
  [[ "$status" == "404" ]] && break
  sleep 2
done
[[ "${status:-}" == "404" ]]

for release_namespace in "$ENVPILOT_REMOTE_E2E_AGENT_RELEASE:$ENVPILOT_REMOTE_E2E_AGENT_NAMESPACE" "$ENVPILOT_REMOTE_E2E_RUNNER_RELEASE:$ENVPILOT_REMOTE_E2E_RUNNER_NAMESPACE"; do
  release="${release_namespace%%:*}"
  namespace="${release_namespace#*:}"
  ! helm --kube-context "$ENVPILOT_REMOTE_E2E_REMOTE_CONTEXT" -n "$namespace" status "$release" >/dev/null 2>&1
  kubectl --context "$ENVPILOT_REMOTE_E2E_REMOTE_CONTEXT" -n "$namespace" get pvc -l envpilot.io/managed-remote=true >/dev/null
done

echo "published remote-cluster lifecycle E2E passed"
