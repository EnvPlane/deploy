#!/usr/bin/env bash
set -euo pipefail

# Exercise the exact Helm upgrade path used by legacy remote Runner releases.
# The first install intentionally supplies no controlPlane.tls keys. Helm stores
# only those user values, then the published chart must render an upgrade with
# --reuse-values without dereferencing a missing TLS map.
: "${ENVPILOT_RUNNER_UPGRADE_CONTEXT:?set an already-provisioned Kubernetes context}"
: "${ENVPILOT_RUNNER_UPGRADE_CHART:?set the published OCI Runner chart reference}"
: "${ENVPILOT_RUNNER_UPGRADE_VERSION:?set the immutable Runner chart version}"

namespace="${ENVPILOT_RUNNER_UPGRADE_NAMESPACE:-envpilot-runner-upgrade-test}"
release="${ENVPILOT_RUNNER_UPGRADE_RELEASE:-legacy-remote-runner}"
remote_url="${ENVPILOT_RUNNER_UPGRADE_REMOTE_URL:-https://control-plane.example.invalid}"
deployment="${release}-envpilot-runner"

cleanup() {
  helm uninstall "$release" --kube-context "$ENVPILOT_RUNNER_UPGRADE_CONTEXT" --namespace "$namespace" --wait --timeout 1m >/dev/null 2>&1 || true
  kubectl --context "$ENVPILOT_RUNNER_UPGRADE_CONTEXT" delete namespace "$namespace" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --context "$ENVPILOT_RUNNER_UPGRADE_CONTEXT" get --raw=/version >/dev/null

# Deliberately omit every controlPlane.tls key. replicaCount=0 avoids requiring
# a reachable demonstration endpoint while Helm still creates and upgrades the
# real release resources. Disable the auth PVC only in this disposable test so
# a generic Kind cluster does not need a dynamic storage provisioner.
helm upgrade --install "$release" "$ENVPILOT_RUNNER_UPGRADE_CHART" \
  --version "$ENVPILOT_RUNNER_UPGRADE_VERSION" \
  --kube-context "$ENVPILOT_RUNNER_UPGRADE_CONTEXT" \
  --namespace "$namespace" --create-namespace --wait --timeout 2m \
  --set replicaCount=0 \
  --set controlPlane.authPersistence.createClaim=false \
  --set controlPlane.endpointMode=remote \
  --set controlPlane.url="$remote_url"

stored_values="$(helm get values "$release" --kube-context "$ENVPILOT_RUNNER_UPGRADE_CONTEXT" --namespace "$namespace" -o json)"
jq -e --arg remote_url "$remote_url" '
  .controlPlane.endpointMode == "remote" and
  .controlPlane.url == $remote_url and
  (.controlPlane | has("tls") | not)
' <<<"$stored_values" >/dev/null || {
  echo "legacy release did not retain the expected no-TLS stored values" >&2
  exit 1
}

helm upgrade "$release" "$ENVPILOT_RUNNER_UPGRADE_CHART" \
  --version "$ENVPILOT_RUNNER_UPGRADE_VERSION" \
  --kube-context "$ENVPILOT_RUNNER_UPGRADE_CONTEXT" \
  --namespace "$namespace" --reuse-values --wait --timeout 2m \
  --set controlPlane.endpointMode=remote

rendered_endpoint="$(kubectl --context "$ENVPILOT_RUNNER_UPGRADE_CONTEXT" --namespace "$namespace" get deployment "$deployment" -o jsonpath='{.spec.template.spec.containers[?(@.name=="runner")].env[?(@.name=="ENVPILOT_CONTROL_PLANE_URL")].value}')"
test "$rendered_endpoint" = "$remote_url" || {
  echo "published Runner chart did not retain the remote endpoint on --reuse-values upgrade" >&2
  exit 1
}

ca_env_count="$(kubectl --context "$ENVPILOT_RUNNER_UPGRADE_CONTEXT" --namespace "$namespace" get deployment "$deployment" -o json | jq '[.spec.template.spec.containers[]?.env[]? | select(.name == "ENVPILOT_CONTROL_PLANE_CA_FILE")] | length')"
test "$ca_env_count" = 0 || {
  echo "legacy release without controlPlane.tls unexpectedly rendered a CA mount" >&2
  exit 1
}

echo "published Runner legacy --reuse-values remote upgrade passed"
