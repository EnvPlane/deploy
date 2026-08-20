#!/usr/bin/env bash
# Verify the positive browser environment lifecycle against a published
# umbrella chart. The only product installation command below is one
# `helm upgrade --install`; port-forwards are test-harness transport only.
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="${ENVPLANE_WORKSPACE_ROOT:-$(cd "$DEPLOY_ROOT/.." && pwd)}"
: "${ENVPLANE_E2E_CONTEXT:?set an already-provisioned Kubernetes context}"
: "${ENVPLANE_E2E_UMBRELLA_REF:?set the published OCI umbrella ref, e.g. oci://ghcr.io/envplane/envplane}"
: "${ENVPLANE_E2E_UMBRELLA_VERSION:?set the published immutable umbrella version}"

NAMESPACE="${ENVPLANE_E2E_NAMESPACE:-envplane}"
RELEASE="${ENVPLANE_E2E_RELEASE:-envplane}"
PROJECT_ID="${ENVPLANE_E2E_PROJECT_ID:-envplane-e2e-fixture}"
API_PORT="${ENVPLANE_E2E_API_PORT:-18080}"
UI_PORT="${ENVPLANE_E2E_UI_PORT:-13000}"
VALUES_FILE="${ENVPLANE_E2E_VALUES_FILE:-$DEPLOY_ROOT/deploy/helm/envplane/values-e2e-local.yaml}"
API_URL="http://127.0.0.1:${API_PORT}"
UI_URL="http://127.0.0.1:${UI_PORT}"
pids=()

cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT

for bin in helm kubectl curl jq npm; do command -v "$bin" >/dev/null 2>&1 || { echo "missing required command: $bin" >&2; exit 2; }; done
[[ -f "$VALUES_FILE" ]] || { echo "E2E values file does not exist: $VALUES_FILE" >&2; exit 2; }

# This is intentionally the only EnvPlane install invocation.
helm upgrade --install "$RELEASE" "$ENVPLANE_E2E_UMBRELLA_REF" \
  --version "$ENVPLANE_E2E_UMBRELLA_VERSION" \
  --kube-context "$ENVPLANE_E2E_CONTEXT" \
  --namespace "$NAMESPACE" --create-namespace \
  --values "$VALUES_FILE" --wait --timeout 15m

kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envplane-control-plane --timeout=5m
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envplane-agent --timeout=5m
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envplane-runner --timeout=5m
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n envplane-e2e-base rollout status deployment/e2e-base-workload --timeout=5m

kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envplane-control-plane "${API_PORT}:8080" >/tmp/envplane-e2e-api-port-forward.log 2>&1 & pids+=("$!")
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envplane-frontend "${UI_PORT}:3000" >/tmp/envplane-e2e-ui-port-forward.log 2>&1 & pids+=("$!")
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

# A second identical release invocation is the repeat-run portion of the
# fixture contract. The reconciler must preserve consumed credentials and the
# compiled session rather than require a new Secret or a manual restart.
helm upgrade --install "$RELEASE" "$ENVPLANE_E2E_UMBRELLA_REF" \
  --version "$ENVPLANE_E2E_UMBRELLA_VERSION" \
  --kube-context "$ENVPLANE_E2E_CONTEXT" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" --wait --timeout 15m
for _ in $(seq 1 120); do
  project="$(curl -fsS "$API_URL/api/v1/projects/$PROJECT_ID" 2>/dev/null || true)"
  if [[ "$(jq -r '.deployment_readiness.ready // false' <<<"$project")" == "true" ]]; then break; fi
  sleep 2
done
[[ "$(jq -r '.deployment_readiness.ready // false' <<<"$project")" == "true" ]] || {
  jq '.deployment_readiness' <<<"$project" >&2
  echo "fixture project lost deploy-readiness after idempotent repeat run" >&2
  exit 1
}

cd "$WORKSPACE_ROOT/frontend"
ENVPLANE_E2E_REAL_CLUSTER=1 \
ENVPLANE_E2E_RUN_LIFECYCLE=1 \
ENVPLANE_E2E_PROJECT_ID="$PROJECT_ID" \
ENVPLANE_E2E_API_URL="$API_URL" \
ENVPLANE_E2E_BASE_URL="$UI_URL" \
ENVPLANE_DISABLE_WEB_SERVER=1 \
npm run test:e2e -- --grep 'creates a real full environment through the UI'
