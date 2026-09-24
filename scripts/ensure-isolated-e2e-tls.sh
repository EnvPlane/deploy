#!/usr/bin/env bash
set -euo pipefail

# Maintains only an explicitly selected, reusable two-Kind-cluster E2E endpoint.
# Never use this helper for a production certificate or a non-Kind context.
mode="${1:-check}"
minimum_seconds="${ENVPLANE_E2E_TLS_MIN_VALID_SECONDS:-604800}"
valid_days="${ENVPLANE_E2E_TLS_VALID_DAYS:-30}"
[[ "$minimum_seconds" =~ ^[0-9]+$ && "$valid_days" =~ ^[0-9]+$ ]] || { echo 'TLS lifetime settings must be positive integers' >&2; exit 2; }
(( minimum_seconds > 0 && valid_days > 0 && valid_days * 86400 > minimum_seconds )) || { echo 'new certificate lifetime must exceed the minimum remaining lifetime' >&2; exit 2; }

validate_certificate_identity() {
  local certificate="$1" host="$2"
  openssl x509 -in "$certificate" -noout -ext subjectAltName | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -Fxq "DNS:$host" || {
    echo "certificate SAN does not contain DNS:$host" >&2
    return 2
  }
}

certificate_lifetime() {
  local certificate="$1" end_date end_epoch now_epoch remaining
  end_date="$(openssl x509 -in "$certificate" -noout -enddate | cut -d= -f2-)"
  if end_epoch="$(date -u -d "$end_date" +%s 2>/dev/null)"; then
    :
  else
    end_epoch="$(date -j -u -f '%b %e %T %Y %Z' "$end_date" +%s)"
  fi
  now_epoch="$(date -u +%s)"
  remaining="$((end_epoch - now_epoch))"
  echo "isolated E2E TLS expires at $end_date; remaining seconds: $remaining"
  (( remaining >= minimum_seconds ))
}

if [[ "$mode" == check-file ]]; then
  [[ "$#" == 3 && -r "$2" && -n "$3" ]] || { echo 'usage: check-file CERTIFICATE HOST' >&2; exit 2; }
  validate_certificate_identity "$2" "$3"
  certificate_lifetime "$2"
  exit
fi
[[ "$mode" == check || "$mode" == ensure ]] || { echo 'usage: check|ensure|check-file' >&2; exit 2; }

: "${ENVPLANE_E2E_MANAGEMENT_CONTEXT:?set the isolated management Kind context}"
: "${ENVPLANE_E2E_TARGET_CONTEXT:?set the isolated target Kind context}"
: "${ENVPLANE_E2E_REMOTE_CLUSTER_ID:?set the isolated remote cluster ID}"
management_context="$ENVPLANE_E2E_MANAGEMENT_CONTEXT"
target_context="$ENVPLANE_E2E_TARGET_CONTEXT"
cluster_id="$ENVPLANE_E2E_REMOTE_CLUSTER_ID"
namespace="${ENVPLANE_E2E_NAMESPACE:-envplane-e2e}"
remote_namespace="${ENVPLANE_E2E_REMOTE_NAMESPACE:-envplane-system}"
endpoint_deployment="${ENVPLANE_E2E_TLS_ENDPOINT_DEPLOYMENT:-e2e-management-endpoint}"
endpoint_secret="${ENVPLANE_E2E_TLS_ENDPOINT_SECRET:-${endpoint_deployment}-tls}"
endpoint_host="${ENVPLANE_E2E_TLS_ENDPOINT_HOST:-management.e2e.internal}"
source_ca_secret="${ENVPLANE_E2E_REMOTE_CONTROL_PLANE_CA_SECRET:-${cluster_id}-management-ca}"
extra_ca_secret="${ENVPLANE_E2E_TLS_EXTRA_MANAGEMENT_CA_SECRET:-${cluster_id}-control-plane-ca}"
target_ca_secret="${ENVPLANE_E2E_REMOTE_TARGET_CA_SECRET:-${cluster_id}-control-plane-ca}"

for binary in base64 grep jq kind kubectl openssl; do command -v "$binary" >/dev/null || { echo "missing $binary" >&2; exit 2; }; done
[[ "$management_context" == kind-* && "$target_context" == kind-* && "$management_context" != "$target_context" ]] || {
  echo 'both contexts must be distinct Kind contexts' >&2; exit 2;
}
kind get clusters | grep -Fxq "${management_context#kind-}" || { echo 'management Kind cluster not found' >&2; exit 2; }
kind get clusters | grep -Fxq "${target_context#kind-}" || { echo 'target Kind cluster not found' >&2; exit 2; }
for name in "$cluster_id" "$namespace" "$remote_namespace" "$endpoint_deployment" "$endpoint_secret" "$source_ca_secret" "$extra_ca_secret" "$target_ca_secret"; do
  [[ "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || { echo "invalid Kubernetes resource name: $name" >&2; exit 2; }
done
[[ "$endpoint_host" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]] || { echo 'invalid endpoint DNS name' >&2; exit 2; }

temporary_directory="$(mktemp -d /tmp/envplane-isolated-e2e-tls.XXXXXX)"
chmod 700 "$temporary_directory"
cleanup() {
  rm -f "$temporary_directory/current.crt" "$temporary_directory/new.crt" "$temporary_directory/new.key" \
    "$temporary_directory/bundle.crt" "$temporary_directory/ca.crt"
  rmdir "$temporary_directory"
}
trap cleanup EXIT
kubectl --context "$management_context" -n "$namespace" get deployment "$endpoint_deployment" >/dev/null
kubectl --context "$management_context" -n "$namespace" get secret "$endpoint_secret" -o 'jsonpath={.data.tls\.crt}' | base64 -d >"$temporary_directory/current.crt"
openssl x509 -in "$temporary_directory/current.crt" -noout >/dev/null
validate_certificate_identity "$temporary_directory/current.crt" "$endpoint_host"

remote_deployments=()
while IFS= read -r deployment_name; do
  [[ -n "$deployment_name" ]] && remote_deployments+=("$deployment_name")
done < <(kubectl --context "$target_context" -n "$remote_namespace" get deployments -o json | jq -r --arg secret "$target_ca_secret" \
  '.items[] | select(any(.spec.template.spec.volumes[]?; .secret.secretName == $secret)) | .metadata.name')
(( ${#remote_deployments[@]} > 0 )) || { echo 'no isolated remote deployments mount the target CA Secret' >&2; exit 2; }

trust_matches() {
  local context="$1" secret_namespace="$2" secret_name="$3" expected_fingerprint="$4" actual_fingerprint
  kubectl --context "$context" -n "$secret_namespace" get secret "$secret_name" -o 'jsonpath={.data.ca\.crt}' | base64 -d >"$temporary_directory/ca.crt"
  [[ "$(grep -c -- '-----BEGIN CERTIFICATE-----' "$temporary_directory/ca.crt")" == 1 ]] || return 1
  actual_fingerprint="$(openssl x509 -in "$temporary_directory/ca.crt" -noout -fingerprint -sha256)"
  [[ "$actual_fingerprint" == "$expected_fingerprint" ]]
}

current_fingerprint="$(openssl x509 -in "$temporary_directory/current.crt" -noout -fingerprint -sha256)"
trust_ready=true
for secret_name in "$source_ca_secret" "$extra_ca_secret"; do
  trust_matches "$management_context" "$namespace" "$secret_name" "$current_fingerprint" || trust_ready=false
done
trust_matches "$target_context" "$remote_namespace" "$target_ca_secret" "$current_fingerprint" || trust_ready=false
lifetime_ready=true
certificate_lifetime "$temporary_directory/current.crt" || lifetime_ready=false
if [[ "$mode" == check ]]; then
  [[ "$lifetime_ready" == true && "$trust_ready" == true ]] || { echo 'isolated E2E TLS requires renewal or trust repair' >&2; exit 1; }
  echo 'isolated E2E TLS preflight passed'
  exit 0
fi
if [[ "$lifetime_ready" == true && "$trust_ready" == true ]]; then
  echo 'isolated E2E TLS is current; no changes required'
  exit 0
fi

apply_ca_secret() {
  local context="$1" secret_namespace="$2" secret_name="$3" certificate_file="$4"
  kubectl create secret generic "$secret_name" --from-file="ca.crt=$certificate_file" --dry-run=client -o yaml | \
    kubectl --context "$context" -n "$secret_namespace" apply --server-side --force-conflicts \
      --field-manager=envplane-isolated-e2e-tls -f - >/dev/null
}
apply_all_ca_secrets() {
  local certificate_file="$1" secret_name
  for secret_name in "$source_ca_secret" "$extra_ca_secret"; do
    apply_ca_secret "$management_context" "$namespace" "$secret_name" "$certificate_file"
  done
  apply_ca_secret "$target_context" "$remote_namespace" "$target_ca_secret" "$certificate_file"
}
restart_remote_deployments() {
  local deployment_name
  for deployment_name in "${remote_deployments[@]}"; do
    kubectl --context "$target_context" -n "$remote_namespace" rollout restart "deployment/$deployment_name" >/dev/null
  done
  for deployment_name in "${remote_deployments[@]}"; do
    kubectl --context "$target_context" -n "$remote_namespace" rollout status "deployment/$deployment_name" --timeout=5m >/dev/null
  done
}

if [[ "$lifetime_ready" != true ]]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -days "$valid_days" -nodes \
    -keyout "$temporary_directory/new.key" -out "$temporary_directory/new.crt" \
    -subj "/CN=$endpoint_host" -addext "subjectAltName=DNS:$endpoint_host" >/dev/null 2>&1
  validate_certificate_identity "$temporary_directory/new.crt" "$endpoint_host"
  certificate_lifetime "$temporary_directory/new.crt" >/dev/null
  # Stage overlapping trust before replacing the served certificate.
  awk '1' "$temporary_directory/current.crt" "$temporary_directory/new.crt" >"$temporary_directory/bundle.crt"
  apply_all_ca_secrets "$temporary_directory/bundle.crt"
  kubectl create secret tls "$endpoint_secret" --cert="$temporary_directory/new.crt" --key="$temporary_directory/new.key" --dry-run=client -o yaml | \
    kubectl --context "$management_context" -n "$namespace" apply --server-side --force-conflicts \
      --field-manager=envplane-isolated-e2e-tls -f - >/dev/null
  kubectl --context "$management_context" -n "$namespace" rollout restart "deployment/$endpoint_deployment" >/dev/null
  kubectl --context "$management_context" -n "$namespace" rollout status "deployment/$endpoint_deployment" --timeout=5m >/dev/null
  # Remove the expired trust anchor after the new endpoint is serving.
  apply_all_ca_secrets "$temporary_directory/new.crt"
else
  apply_all_ca_secrets "$temporary_directory/current.crt"
fi
restart_remote_deployments
echo 'isolated E2E TLS renewed; rerun preflight after reconciliation'
