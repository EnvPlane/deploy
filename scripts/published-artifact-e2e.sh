#!/usr/bin/env bash
set -euo pipefail

# Published-artifact E2E. The target cluster must already exist; this harness
# never creates a cluster and has no minikube-specific behavior.
: "${ENVPLANE_E2E_CONTEXT:?set the already-provisioned kube context}"
: "${ENVPLANE_E2E_VALUES_FILE:?set a values file for this published release}"
: "${ENVPLANE_E2E_CHART_N_MINUS_1:?set the published N-1 umbrella chart ref}"
: "${ENVPLANE_E2E_CHART_N:?set the published N umbrella chart ref}"

NAMESPACE="${ENVPLANE_E2E_NAMESPACE:-envplane}"
RELEASE="${ENVPLANE_E2E_RELEASE:-envplane}"
API_PORT="${ENVPLANE_E2E_API_PORT:-18080}"
UI_PORT="${ENVPLANE_E2E_UI_PORT:-13000}"
API_URL="http://127.0.0.1:${API_PORT}"
UI_URL="http://127.0.0.1:${UI_PORT}"
PROJECT_ID="${ENVPLANE_E2E_PROJECT_ID:-published-e2e}"
ENVIRONMENT_ID="${ENVPLANE_E2E_ENVIRONMENT_ID:-published-e2e-env}"
PROJECT_PAYLOAD="${ENVPLANE_E2E_PROJECT_PAYLOAD:-{\"name\":\"Published E2E\",\"product_id\":\"generic\"}}"
ENVIRONMENT_PAYLOAD="${ENVPLANE_E2E_ENVIRONMENT_PAYLOAD:-{\"id\":\"${ENVIRONMENT_ID}\",\"project\":\"${PROJECT_ID}\",\"mode\":\"full\"}}"
ROLLBACK_REVISION="${ENVPLANE_E2E_ROLLBACK_REVISION:-1}"
tmp="$(mktemp -d)"
pf_pids=()
trap 'for pid in "${pf_pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$tmp"' EXIT

kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" get namespace "$NAMESPACE" >/dev/null

# Exactly one application install command, using only the values file.
helm upgrade --install "$RELEASE" "$ENVPLANE_E2E_CHART_N_MINUS_1" \
  --kube-context "$ENVPLANE_E2E_CONTEXT" --namespace "$NAMESPACE" --values "$ENVPLANE_E2E_VALUES_FILE" --reset-values --wait --timeout 15m

kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envplane-control-plane "${API_PORT}:8080" >/tmp/envplane-published-api-pf.log 2>&1 & pf_pids+=("$!")
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envplane-frontend "${UI_PORT}:3000" >/tmp/envplane-published-ui-pf.log 2>&1 & pf_pids+=("$!")
for _ in $(seq 1 60); do
  curl -fsS "$API_URL/api/v1/health" >/dev/null 2>&1 && curl -fsS "$UI_URL/" >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS "$API_URL/api/v1/health" >/dev/null
curl -fsS "$UI_URL/" >/dev/null

kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" wait --for=condition=available deployment -l app.kubernetes.io/component=cluster-agent --timeout=5m
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" wait --for=condition=available deployment -l app.kubernetes.io/name=envplane-runner --timeout=5m
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
helm upgrade "$RELEASE" "$ENVPLANE_E2E_CHART_N" --kube-context "$ENVPLANE_E2E_CONTEXT" --namespace "$NAMESPACE" --values "$ENVPLANE_E2E_VALUES_FILE" --reset-values --wait --timeout 15m
curl -fsS "$API_URL/api/v1/health" >/dev/null
helm rollback "$RELEASE" "$ROLLBACK_REVISION" --kube-context "$ENVPLANE_E2E_CONTEXT" --namespace "$NAMESPACE" --wait --timeout 15m
curl -fsS "$API_URL/api/v1/health" >/dev/null

helm uninstall "$RELEASE" --kube-context "$ENVPLANE_E2E_CONTEXT" --namespace "$NAMESPACE" --wait
if kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" get configmap "${RELEASE}-platform-dependency-status" >/dev/null 2>&1; then
  echo "EnvPlane release resources remain after uninstall" >&2
  exit 1
fi
if [[ -n "${ENVPLANE_E2E_EXISTING_RESOURCES:-}" ]]; then
  IFS=',' read -r -a resources <<< "$ENVPLANE_E2E_EXISTING_RESOURCES"
  for resource in "${resources[@]}"; do
    kubectl --context "$ENVPLANE_E2E_CONTEXT" get "$resource" >/dev/null
  done
fi
