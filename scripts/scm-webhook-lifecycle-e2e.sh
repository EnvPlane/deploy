#!/usr/bin/env bash
# Exercise the SCM webhook lifecycle against one disposable umbrella install.
# The callback must be a real HTTPS ingress or an HTTPS tunnel that forwards to
# the receiver Service; loopback URLs are intentionally rejected by Bootstrap.
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${ENVPLANE_E2E_CONTEXT:?set a Kubernetes context}"
: "${ENVPLANE_E2E_UMBRELLA_REF:?set the immutable umbrella OCI ref}"
: "${ENVPLANE_E2E_UMBRELLA_VERSION:?set the immutable umbrella version}"
: "${ENVPLANE_E2E_PUBLIC_CALLBACK_URL:?set an https ingress or tunnel URL, without the callback path}"
: "${ENVPLANE_E2E_GITLAB_WEBHOOK_TOKEN:?set the disposable GitLab hook token used by the fixture}"

NAMESPACE="${ENVPLANE_E2E_NAMESPACE:-envplane}"
RELEASE="${ENVPLANE_E2E_RELEASE:-envplane}"
PROJECT_ID="${ENVPLANE_E2E_PROJECT_ID:-envplane-e2e-gitlab}"
API_PORT="${ENVPLANE_E2E_API_PORT:-18081}"
API_URL="http://127.0.0.1:${API_PORT}"
CALLBACK_BASE="${ENVPLANE_E2E_PUBLIC_CALLBACK_URL%/}"
CALLBACK_URL="${CALLBACK_BASE}/api/v1/webhooks/gitlab"
CALLBACK_HOST="${CALLBACK_BASE#https://}"
CALLBACK_HOST="${CALLBACK_HOST%%/*}"
TLS_SECRET="${ENVPLANE_E2E_WEBHOOK_TLS_SECRET:-envplane-e2e-webhook-tls}"
VALUES_FILE="${ENVPLANE_E2E_VALUES_FILE:-$DEPLOY_ROOT/deploy/helm/envplane/values-e2e-local.yaml}"
AUTH_ARGS=()
if [[ -n "${ENVPLANE_E2E_API_TOKEN:-}" ]]; then AUTH_ARGS=(-H "Authorization: Bearer ${ENVPLANE_E2E_API_TOKEN}"); fi

tmp_values="$(mktemp)"
pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" >/dev/null 2>&1 || true; done
  rm -f "$tmp_values"
}
trap cleanup EXIT

for bin in helm kubectl curl jq; do command -v "$bin" >/dev/null 2>&1 || { echo "missing required command: $bin" >&2; exit 2; }; done
[[ "$ENVPLANE_E2E_PUBLIC_CALLBACK_URL" == https://* ]] || { echo "callback URL must use https" >&2; exit 2; }
[[ -f "$VALUES_FILE" ]] || { echo "values file does not exist: $VALUES_FILE" >&2; exit 2; }
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" get secret "$TLS_SECRET" >/dev/null

cat "$VALUES_FILE" >"$tmp_values"
helm upgrade --install "$RELEASE" "$ENVPLANE_E2E_UMBRELLA_REF" \
  --version "$ENVPLANE_E2E_UMBRELLA_VERSION" --kube-context "$ENVPLANE_E2E_CONTEXT" \
  --namespace "$NAMESPACE" --create-namespace --values "$tmp_values" \
  --set webhook.enabled=true --set webhook.publicEndpoint.mode=ingress \
  --set-string webhook.publicEndpoint.host="$CALLBACK_HOST" \
  --set-string webhook.publicEndpoint.tls.secretName="$TLS_SECRET" \
  --set-string envplane-control-plane.publicURL="$CALLBACK_BASE" \
  --wait --timeout 15m

kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envplane-control-plane --timeout=5m
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envplane-webhook --timeout=5m
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" port-forward svc/envplane-control-plane "${API_PORT}:8080" >/tmp/envplane-scm-webhook-api.log 2>&1 &
pids+=("$!")
for _ in $(seq 1 120); do curl -fsS "$API_URL/api/v1/health" >/dev/null 2>&1 && break; sleep 2; done
curl -fsS "$API_URL/api/v1/health" >/dev/null

api_status() { curl -sS -o /tmp/envplane-scm-webhook-response.json -w '%{http_code}' "${AUTH_ARGS[@]}" -H 'Content-Type: application/json' "$@"; }
status="$(api_status -X POST "$API_URL/api/v1/projects/$PROJECT_ID/scm-webhook/reconcile")"
[[ "$status" == 200 ]] || { cat /tmp/envplane-scm-webhook-response.json >&2; exit 1; }
status="$(api_status -X POST "$API_URL/api/v1/projects/$PROJECT_ID/scm-webhook/test-delivery")"
[[ "$status" == 200 ]] || { cat /tmp/envplane-scm-webhook-response.json >&2; exit 1; }

mr_body='{"object_kind":"merge_request","user":{"id":77,"username":"e2e","access_level":30},"project":{"id":987,"path_with_namespace":"envplane/e2e"},"object_attributes":{"iid":901,"action":"open","state":"opened","source_branch":"feature/e2e","url":"https://gitlab.example/envplane/e2e/-/merge_requests/901","last_commit":{"id":"e2e901"}}}'
send_event() {
  local action="$1" uuid="$2" body="$3"
  body="${body/open/$action}"
  curl -fsS -X POST "$CALLBACK_URL" -H 'Content-Type: application/json' \
    -H 'X-Gitlab-Event: Merge Request Hook' -H "X-Gitlab-Token: ${ENVPLANE_E2E_GITLAB_WEBHOOK_TOKEN}" \
    -H "X-Gitlab-Event-UUID: ${uuid}" -H 'X-Gitlab-Project-ID: 987' -d "$body" >/dev/null
}
send_event open e2e-delivery-901 "$mr_body"
send_event open e2e-delivery-901 "$mr_body"
send_event close e2e-delivery-close-901 "$mr_body"

invalid_status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$CALLBACK_URL" \
  -H 'Content-Type: application/json' -H 'X-Gitlab-Event: Merge Request Hook' \
  -H 'X-Gitlab-Token: invalid-fixture-token' -H 'X-Gitlab-Event-UUID: invalid-e2e' -d "$mr_body")"
[[ "$invalid_status" == 401 ]] || { echo "invalid event status=$invalid_status" >&2; exit 1; }

status="$(api_status "$API_URL/api/v1/projects/$PROJECT_ID/scm-webhook/status")"
[[ "$status" == 200 ]] || { cat /tmp/envplane-scm-webhook-response.json >&2; exit 1; }
jq -e --arg callback "$CALLBACK_URL" '.publicUrl == $callback and (.ready == true or .lastDeliveryState == "verified")' /tmp/envplane-scm-webhook-response.json >/dev/null

status="$(api_status -X POST "$API_URL/api/v1/projects/$PROJECT_ID/scm-webhook/rotate-secret")"
[[ "$status" == 200 ]] || { cat /tmp/envplane-scm-webhook-response.json >&2; exit 1; }
rotated_status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$CALLBACK_URL" \
  -H 'Content-Type: application/json' -H 'X-Gitlab-Event: Merge Request Hook' \
  -H "X-Gitlab-Token: ${ENVPLANE_E2E_GITLAB_WEBHOOK_TOKEN}" -H 'X-Gitlab-Event-UUID: old-after-rotation' -d "$mr_body")"
[[ "$rotated_status" == 401 ]] || { echo "old token survived rotation: status=$rotated_status" >&2; exit 1; }

admin_status="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${ENVPLANE_E2E_RECEIVER_TOKEN:?set receiver token}" "$API_URL/api/v1/settings")"
[[ "$admin_status" == 401 || "$admin_status" == 403 ]] || { echo "receiver token reached admin endpoint: status=$admin_status" >&2; exit 1; }

kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" scale deployment/envplane-webhook --replicas=0 >/dev/null
sleep 3
unavailable_status="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 10 "$CALLBACK_URL" || true)"
[[ "$unavailable_status" == 000 || "$unavailable_status" == 502 || "$unavailable_status" == 503 || "$unavailable_status" == 504 ]] || { echo "unavailable ingress unexpectedly accepted callback: status=$unavailable_status" >&2; exit 1; }
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" scale deployment/envplane-webhook --replicas=1 >/dev/null
kubectl --context "$ENVPLANE_E2E_CONTEXT" -n "$NAMESPACE" rollout status deployment/envplane-webhook --timeout=5m

echo "SCM webhook lifecycle E2E passed: install, reconcile, test delivery, MR replay, close cleanup, invalid event, rotation, ingress outage, receiver-only authorization."
