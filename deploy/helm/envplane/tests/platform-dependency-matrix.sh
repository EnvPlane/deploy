#!/usr/bin/env bash
set -euo pipefail

: "${PLATFORM_E2E_CONTEXT:?set a comma-separated list of kube contexts}"
NAMESPACE="${PLATFORM_E2E_NAMESPACE:-envplane-e2e-platform}"
RELEASE="${PLATFORM_E2E_RELEASE:-envplane-platform-e2e}"
CHART="${PLATFORM_E2E_CHART:-./deploy/helm/envplane}"
MATRIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/platform-dependencies"
API_PORT="${PLATFORM_E2E_API_PORT:-18080}"
tmp="$(mktemp -d)"
api_pf_pid=""

cleanup() {
  if [[ -n "$api_pf_pid" ]]; then
    kill "$api_pf_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

assert_capabilities_match_observed_status() {
  local context="$1"
  local expected_ingress_state="$2"
  local pod capabilities
  pod="$(kubectl --context "$context" -n "$NAMESPACE" get pods -l app.kubernetes.io/name=envplane-control-plane -o jsonpath='{.items[0].metadata.name}')"
  test -n "$pod"
  kubectl --context "$context" -n "$NAMESPACE" port-forward "pod/$pod" "${API_PORT}:8080" >"$tmp/api-port-forward.log" 2>&1 &
  api_pf_pid="$!"
  for _ in $(seq 1 30); do
    if capabilities="$(curl -fsS "http://127.0.0.1:${API_PORT}/api/v1/capabilities" 2>/dev/null)"; then
      break
    fi
    sleep 1
  done
  test -n "${capabilities:-}"
  printf '%s\n' "$capabilities" | jq -e --arg state "$expected_ingress_state" '
    .platformDependencyStatus.state == "observed" and
    .platformDependencies.ingress.state == $state and
    .platformDependencies.ingress.generation >= 1 and
    (.platformDependencyStatus.observedAt | type == "string")
  ' >/dev/null
  kill "$api_pf_pid" 2>/dev/null || true
  wait "$api_pf_pid" 2>/dev/null || true
  api_pf_pid=""
}

IFS=',' read -r -a contexts <<< "$PLATFORM_E2E_CONTEXT"
for context in "${contexts[@]}"; do
  for scenario in empty existing mixed degraded; do
    values="$MATRIX_DIR/$scenario.yaml"
    echo "==> context=$context scenario=$scenario"
    if [[ "$scenario" == degraded ]]; then
      set +e
      helm upgrade --install "$RELEASE" "$CHART" --kube-context "$context" \
        --namespace "$NAMESPACE" --create-namespace --values "$values" \
        --set platformDependencyReconciler.enabled=true --wait --timeout 10m
      rc=$?
      set -e
      test "$rc" -ne 0
    else
      helm upgrade --install "$RELEASE" "$CHART" --kube-context "$context" \
        --namespace "$NAMESPACE" --create-namespace --values "$values" \
        --set platformDependencyReconciler.enabled=true --wait --timeout 10m
    fi
    revision="$(helm status "$RELEASE" --kube-context "$context" --namespace "$NAMESPACE" -o json | jq -r '.version')"
    status="$(kubectl --context "$context" -n "$NAMESPACE" get configmap "${RELEASE}-platform-dependency-reconciler-status-r${revision}" -o jsonpath='{.data.status\.json}')"
    test -n "$status"
    printf '%s\n' "$status" | jq -e '
      type == "object" and
      .schemaVersion == 1 and
      (.generation | type == "number") and
      (.observedAt | type == "string") and
      (.dependencies | type == "object") and
      (.dependencies | has("ingress") and has("dns") and has("storage"))
    ' >/dev/null

    if [[ "$scenario" != degraded ]]; then
      ingress_state="$(printf '%s\n' "$status" | jq -r '.dependencies.ingress.state')"
      assert_capabilities_match_observed_status "$context" "$ingress_state"
    fi

    # Reinstalling healthy scenarios must be idempotent. The degraded case is
    # expected to remain blocked with the same actionable diagnostic.
    if [[ "$scenario" != degraded ]]; then
      helm upgrade --install "$RELEASE" "$CHART" --kube-context "$context" \
        --namespace "$NAMESPACE" --values "$values" \
        --set platformDependencyReconciler.enabled=true --wait --timeout 10m >/dev/null
    fi

    helm uninstall "$RELEASE" --kube-context "$context" --namespace "$NAMESPACE" --wait
    # Detected/external resources must survive uninstall; managed resources are
    # removed according to cleanupPolicy by the pre-delete hook.
  done
done
