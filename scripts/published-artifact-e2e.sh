#!/usr/bin/env bash
set -euo pipefail

# Published-artifact E2E. The target cluster must already exist; this harness
# never creates a cluster and has no minikube-specific behavior.
: "${ENVPILOT_E2E_CONTEXT:?set the already-provisioned kube context}"
: "${ENVPILOT_E2E_VALUES_FILE:?set a values file for this published release}"
: "${ENVPILOT_E2E_CHART_N_MINUS_1:?set the published N-1 umbrella chart ref}"
: "${ENVPILOT_E2E_CHART_N:?set the published N umbrella chart ref}"

NAMESPACE="${ENVPILOT_E2E_NAMESPACE:-envpilot}"
RELEASE="${ENVPILOT_E2E_RELEASE:-envpilot}"
API_PORT="${ENVPILOT_E2E_API_PORT:-18080}"
UI_PORT="${ENVPILOT_E2E_UI_PORT:-13000}"
API_URL="http://127.0.0.1:${API_PORT}"
UI_URL="http://127.0.0.1:${UI_PORT}"
PROJECT_ID="${ENVPILOT_E2E_PROJECT_ID:-published-e2e}"
ENVIRONMENT_ID="${ENVPILOT_E2E_ENVIRONMENT_ID:-published-e2e-env}"
PROJECT_PAYLOAD="${ENVPILOT_E2E_PROJECT_PAYLOAD:-{\"name\":\"Published E2E\",\"product_id\":\"generic\"}}"
ENVIRONMENT_PAYLOAD="${ENVPILOT_E2E_ENVIRONMENT_PAYLOAD:-{\"id\":\"${ENVIRONMENT_ID}\",\"project_id\":\"${PROJECT_ID}\",\"mode\":\"full\"}}"
ROLLBACK_REVISION="${ENVPILOT_E2E_ROLLBACK_REVISION:-1}"
tmp="$(mktemp -d)"
pf_pids=()
trap 'for pid in "${pf_pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$tmp"' EXIT

kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" get namespace "$NAMESPACE" >/dev/null

# Exactly one application install command, using only the values file.
helm upgrade --install "$RELEASE" "$ENVPILOT_E2E_CHART_N_MINUS_1" \
  --kube-context "$ENVPILOT_E2E_CONTEXT" --namespace "$NAMESPACE" --values "$ENVPILOT_E2E_VALUES_FILE" --reset-values --wait --timeout 15m

kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envpilot-control-plane "${API_PORT}:8080" >/tmp/envpilot-published-api-pf.log 2>&1 & pf_pids+=("$!")
kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envpilot-frontend "${UI_PORT}:3000" >/tmp/envpilot-published-ui-pf.log 2>&1 & pf_pids+=("$!")
for _ in $(seq 1 60); do
  curl -fsS "$API_URL/api/v1/health" >/dev/null 2>&1 && curl -fsS "$UI_URL/" >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS "$API_URL/api/v1/health" >/dev/null
curl -fsS "$UI_URL/" >/dev/null

kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" wait --for=condition=available deployment -l app.kubernetes.io/component=cluster-agent --timeout=5m
kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" wait --for=condition=available deployment -l app.kubernetes.io/name=envpilot-runner --timeout=5m
curl -fsS "$API_URL/api/v1/runners/health" >/dev/null

curl -fsS -X PUT "$API_URL/api/v1/projects/$PROJECT_ID" -H 'content-type: application/json' -d "$PROJECT_PAYLOAD" >"$tmp/project.json"
curl -fsS -X POST "$API_URL/api/v1/environments" -H 'content-type: application/json' -d "$ENVIRONMENT_PAYLOAD" >"$tmp/environment.json"
for _ in $(seq 1 90); do
  body="$(curl -fsS "$API_URL/api/v1/environments/$ENVIRONMENT_ID")"
  if printf '%s' "$body" | jq -e '(.status // "") | IN("ready", "succeeded", "completed")' >/dev/null 2>&1; then break; fi
  if printf '%s' "$body" | jq -e '(.status // "") | IN("failed", "error")' >/dev/null 2>&1; then echo "$body" >&2; exit 1; fi
  sleep 2
done
curl -fsS "$API_URL/api/v1/environments/$ENVIRONMENT_ID" | jq -e '(.status // "") | IN("ready", "succeeded", "completed")' >/dev/null

# Do not use --reuse-values here: it retains the prior nested image maps and
# defeats the immutable pins selected by the N chart's compatibility manifest.
helm upgrade "$RELEASE" "$ENVPILOT_E2E_CHART_N" --kube-context "$ENVPILOT_E2E_CONTEXT" --namespace "$NAMESPACE" --values "$ENVPILOT_E2E_VALUES_FILE" --reset-values --wait --timeout 15m
curl -fsS "$API_URL/api/v1/health" >/dev/null
helm rollback "$RELEASE" "$ROLLBACK_REVISION" --kube-context "$ENVPILOT_E2E_CONTEXT" --namespace "$NAMESPACE" --wait --timeout 15m
curl -fsS "$API_URL/api/v1/health" >/dev/null

helm uninstall "$RELEASE" --kube-context "$ENVPILOT_E2E_CONTEXT" --namespace "$NAMESPACE" --wait
if kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" get configmap "${RELEASE}-platform-dependency-status" >/dev/null 2>&1; then
  echo "EnvPlane release resources remain after uninstall" >&2
  exit 1
fi
if [[ -n "${ENVPILOT_E2E_EXISTING_RESOURCES:-}" ]]; then
  IFS=',' read -r -a resources <<< "$ENVPILOT_E2E_EXISTING_RESOURCES"
  for resource in "${resources[@]}"; do
    kubectl --context "$ENVPILOT_E2E_CONTEXT" get "$resource" >/dev/null
  done
fi
