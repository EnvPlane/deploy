#!/usr/bin/env bash
# Smoke-check the EnvPlane control plane running in minikube.
# Usage: ./scripts/minikube-verify.sh
set -uo pipefail

PROFILE="${MINIKUBE_PROFILE:-envpilot}"
NAMESPACE="${ENVPILOT_NAMESPACE:-envpilot}"
LOCAL_PORT="${ENVPILOT_LOCAL_PORT:-8080}"
BASE="http://127.0.0.1:${LOCAL_PORT}"

fail=0
log() { printf '\n==> %s\n' "$*"; }
ok()  { printf '  OK   %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; fail=1; }

log "Cluster context"
kubectl config use-context "$PROFILE" >/dev/null 2>&1 || true
kubectl cluster-info | head -2 || { bad "cluster unreachable"; exit 1; }

log "Workloads in namespace '$NAMESPACE'"
kubectl -n "$NAMESPACE" get pods -o wide
kubectl -n "$NAMESPACE" get svc,ingress,pvc

log "Readiness"
for res in deploy/envpilot-control-plane deploy/envpilot-control-plane-frontend \
           statefulset/envpilot-control-plane-postgres statefulset/envpilot-control-plane-redis; do
  if kubectl -n "$NAMESPACE" rollout status "$res" --timeout=120s >/dev/null 2>&1; then
    ok "$res ready"
  else
    bad "$res not ready"
  fi
done

log "Port-forwarding API to ${BASE}"
kubectl -n "$NAMESPACE" port-forward svc/envpilot-control-plane "${LOCAL_PORT}:8080" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID >/dev/null 2>&1' EXIT
sleep 4

check() { # check <path> [expected-http-code]
  local path="$1" want="${2:-200}" code
  code="$(curl -s -o /tmp/envpilot-check.out -w '%{http_code}' "${BASE}${path}")"
  if [[ "$code" == "$want" ]]; then ok "GET $path -> $code"; else bad "GET $path -> $code (want $want)"; fi
}

log "API endpoints"
check /api/v1/health
check /api/v1/capabilities
check /api/v1/products
check /api/v1/projects
check /api/v1/environments
check /api/v1/settings
check /api/v1/metrics
check /api/v1/openapi

log "Health payload"
curl -s "${BASE}/api/v1/health"; echo

log "API capability contract"
capabilities="$(curl -fsS "${BASE}/api/v1/capabilities" 2>/dev/null || true)"
if [[ "$(printf '%s' "$capabilities" | jq -r '.apiContractVersion // empty')" == "1" ]] && [[ "$(printf '%s' "$capabilities" | jq -r '.features.scmOfflineBootstrap // false')" == "true" ]]; then
  ok "SCM offline bootstrap capability advertised"
else
  bad "SCM offline bootstrap capability missing or incompatible: ${capabilities}"
fi

log "Postgres connectivity"
if kubectl -n "$NAMESPACE" exec statefulset/envpilot-control-plane-postgres -- \
     pg_isready -U envpilot -d envpilot >/dev/null 2>&1; then
  ok "postgres accepting connections"
  kubectl -n "$NAMESPACE" exec statefulset/envpilot-control-plane-postgres -- \
    psql -U envpilot -d envpilot -c '\dt' 2>/dev/null | head -20
else
  bad "postgres not ready"
fi

log "Redis connectivity"
if [[ "$(kubectl -n "$NAMESPACE" exec statefulset/envpilot-control-plane-redis -- redis-cli ping 2>/dev/null)" == "PONG" ]]; then
  ok "redis PONG"
else
  bad "redis not responding"
fi

log "Recent API logs"
kubectl -n "$NAMESPACE" logs deploy/envpilot-control-plane --tail=20

if [[ $fail -eq 0 ]]; then
  log "All checks passed. UI: ${BASE}"
else
  log "Some checks failed (see FAIL lines above)."
fi
exit $fail
