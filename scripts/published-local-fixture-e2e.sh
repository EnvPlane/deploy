#!/usr/bin/env bash
# Verify the positive browser environment lifecycle against a published
# umbrella chart. The only product installation command below is one
# `helm upgrade --install`; port-forwards are test-harness transport only.
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="${ENVPILOT_WORKSPACE_ROOT:-$(cd "$DEPLOY_ROOT/.." && pwd)}"
: "${ENVPILOT_E2E_CONTEXT:?set an already-provisioned Kubernetes context}"
: "${ENVPILOT_E2E_UMBRELLA_REF:?set the published OCI umbrella ref, e.g. oci://ghcr.io/envpilot/envpilot}"
: "${ENVPILOT_E2E_UMBRELLA_VERSION:?set the published immutable umbrella version}"

NAMESPACE="${ENVPILOT_E2E_NAMESPACE:-envpilot}"
RELEASE="${ENVPILOT_E2E_RELEASE:-envpilot}"
PROJECT_ID="${ENVPILOT_E2E_PROJECT_ID:-envpilot-e2e-fixture}"
API_PORT="${ENVPILOT_E2E_API_PORT:-18080}"
UI_PORT="${ENVPILOT_E2E_UI_PORT:-13000}"
VALUES_FILE="${ENVPILOT_E2E_VALUES_FILE:-$DEPLOY_ROOT/deploy/helm/envpilot/values-e2e-local.yaml}"
API_URL="http://127.0.0.1:${API_PORT}"
UI_URL="http://127.0.0.1:${UI_PORT}"
pids=()

cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT

for bin in helm kubectl curl jq npm; do command -v "$bin" >/dev/null 2>&1 || { echo "missing required command: $bin" >&2; exit 2; }; done
[[ -f "$VALUES_FILE" ]] || { echo "E2E values file does not exist: $VALUES_FILE" >&2; exit 2; }

# This is intentionally the only EnvPilot install invocation.
helm upgrade --install "$RELEASE" "$ENVPILOT_E2E_UMBRELLA_REF" \
  --version "$ENVPILOT_E2E_UMBRELLA_VERSION" \
  --kube-context "$ENVPILOT_E2E_CONTEXT" \
  --namespace "$NAMESPACE" --create-namespace \
  --values "$VALUES_FILE" --wait --timeout 15m

kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envpilot-control-plane --timeout=5m
kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envpilot-agent --timeout=5m
kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envpilot-runner --timeout=5m
kubectl --context "$ENVPILOT_E2E_CONTEXT" -n envpilot-e2e-base rollout status deployment/e2e-base-workload --timeout=5m

kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envpilot-control-plane "${API_PORT}:8080" >/tmp/envpilot-e2e-api-port-forward.log 2>&1 & pids+=("$!")
kubectl --context "$ENVPILOT_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envpilot-frontend "${UI_PORT}:3000" >/tmp/envpilot-e2e-ui-port-forward.log 2>&1 & pids+=("$!")
for _ in $(seq 1 180); do
  if curl -fsS "$API_URL/api/v1/health" >/dev/null 2>&1 && curl -fsS "$UI_URL/" >/dev/null 2>&1; then break; fi
  sleep 2
done
curl -fsS "$API_URL/api/v1/health" >/dev/null
curl -fsS "$UI_URL/" >/dev/null

for _ in $(seq 1 300); do
  project="$(curl -fsS "$API_URL/api/v1/projects/$PROJECT_ID" 2>/dev/null || true)"
  if [[ "$(jq -r '.deployment_readiness.ready // false' <<<"$project")" == "true" ]]; then break; fi
  sleep 2
done
project="$(curl -fsS "$API_URL/api/v1/projects/$PROJECT_ID")"
[[ "$(jq -r '.deployment_readiness.ready' <<<"$project")" == "true" ]] || {
  jq '.deployment_readiness' <<<"$project" >&2
  echo "fixture project did not reach deploy-ready" >&2
  exit 1
}

cd "$WORKSPACE_ROOT/frontend"
ENVPILOT_E2E_REAL_CLUSTER=1 \
ENVPILOT_E2E_RUN_LIFECYCLE=1 \
ENVPILOT_E2E_PROJECT_ID="$PROJECT_ID" \
ENVPILOT_E2E_API_URL="$API_URL" \
ENVPILOT_E2E_BASE_URL="$UI_URL" \
ENVPILOT_DISABLE_WEB_SERVER=1 \
npm run test:e2e -- --grep 'creates a real full environment through the UI'
