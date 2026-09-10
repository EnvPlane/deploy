#!/usr/bin/env bash
set -euo pipefail

# Read-only migration preflight. Secret values are never read or printed.

context="${ENVPLANE_KUBE_CONTEXT:-${ENVPLANE_E2E_CONTEXT:-}}"
namespace="${ENVPLANE_WEBHOOK_NAMESPACE:-${ENVPLANE_E2E_NAMESPACE:-envplane}}"
release="${ENVPLANE_WEBHOOK_RELEASE:-${ENVPLANE_E2E_RELEASE:-envplane}}"
project_id="${ENVPLANE_WEBHOOK_PROJECT_ID:-}"
api_url="${ENVPLANE_CONTROL_PLANE_URL:-}"
api_token="${ENVPLANE_CONTROL_PLANE_API_TOKEN:-}"
legacy_deadline="${ENVPLANE_WEBHOOK_LEGACY_FALLBACK_UNTIL:-2026-12-31T23:59:59Z}"

command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

kube=(kubectl)
if [[ -n "$context" ]]; then kube+=(--context "$context"); fi
kube+=(--namespace "$namespace")

echo "SCM webhook migration preflight (read-only)"
echo "namespace=$namespace release=$release"
echo "legacyFallbackUntil=$legacy_deadline"

for secret in "${release}-webhook-receiver" "${release}-webhook-secrets" envplane-webhook-secrets; do
  if json=$("${kube[@]}" get secret "$secret" -o json 2>/dev/null); then
    echo "secret=$secret present=true keys=$(jq -c '[.data // {} | keys[]] | sort' <<<"$json")"
  else
    echo "secret=$secret present=false"
  fi
done

status_name="${release}-webhook-receiver-status"
if json=$("${kube[@]}" get configmap "$status_name" -o json 2>/dev/null); then
  jq -r '"receiverStatus=" + ([.data // {} | to_entries[] | select(.key|test("PUBLIC_URL|MODE|INGRESS_STATE|DNS_STATE|TLS_STATE|RUNTIME_STATE|READINESS")) | (.key + "=" + .value)] | sort | join(","))' <<<"$json"
else
  echo "receiverStatus=missing"
fi

legacy_names='ENVPLANE_GITLAB_WEBHOOK_TOKENS|ENVPLANE_GITLAB_WEBHOOK_TOKEN|ENVPLANE_WEBHOOK_LEGACY_LOCAL_GITLAB_VERIFICATION|ENVPLANE_CONTROL_PLANE_TOKEN'
legacy_env_count=0
if json=$("${kube[@]}" get deployment "${release}-webhook" -o json 2>/dev/null); then
  names=$(jq -r '[.spec.template.spec.containers[]?.env[]?.name // empty] | map(select(test("'"$legacy_names"'"))) | sort | join(",")' <<<"$json")
  if [[ -n "$names" ]]; then
    legacy_env_count=$(awk -F, '{print NF}' <<<"$names")
    echo "legacyEnvironmentNames=$names"
  else
    echo "legacyEnvironmentNames=none"
  fi
else
  echo "deployment=${release}-webhook missing"
fi

if [[ -n "$api_url" && -n "$project_id" && -n "$api_token" ]]; then
  echo "apiPreflight=$(curl -fsS -H "Authorization: Bearer $api_token" "$api_url/api/v1/projects/$project_id/scm-webhook/migration-preflight")"
else
  echo "apiPreflight=skipped (set ENVPLANE_CONTROL_PLANE_URL, ENVPLANE_CONTROL_PLANE_API_TOKEN and ENVPLANE_WEBHOOK_PROJECT_ID)"
fi

if (( legacy_env_count > 0 )); then
  echo "migrationReady=false reason=legacy_secret_environment_present"
  exit 1
fi
echo "migrationReady=true"
