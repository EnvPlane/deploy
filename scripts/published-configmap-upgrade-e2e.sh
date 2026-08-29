#!/usr/bin/env bash
set -euo pipefail

# Runs against an already provisioned cluster. It exercises published umbrella
# artifacts, not a local chart checkout: the predecessor has the legacy fixed
# ConfigMap names, while the candidate uses revision-scoped maps. No cluster is
# created and the only injected payload is a safe observed-status fixture.
: "${ENVPLANE_CONFIGMAP_E2E_CONTEXT:?set the already-provisioned kube context}"
: "${ENVPLANE_CONFIGMAP_E2E_VALUES_FILE:?set the published-release values file}"
: "${ENVPLANE_CONFIGMAP_E2E_CHART_N_MINUS_1:?set the published N-1 umbrella chart ref}"
: "${ENVPLANE_CONFIGMAP_E2E_CHART_N:?set the published N umbrella chart ref}"

NAMESPACE="${ENVPLANE_CONFIGMAP_E2E_NAMESPACE:-envplane-configmap-upgrade-e2e}"
RELEASE="${ENVPLANE_CONFIGMAP_E2E_RELEASE:-envplane-configmap-upgrade-e2e}"
OLD_STATUS_MAP="${ENVPLANE_CONFIGMAP_E2E_OLD_STATUS_MAP:-${RELEASE}-platform-dependency-reconciler-status}"
OLD_COMPATIBILITY_MAP="${ENVPLANE_CONFIGMAP_E2E_OLD_COMPATIBILITY_MAP:-${RELEASE}-remote-cluster-compatibility}"

cleanup() {
  helm uninstall "$RELEASE" --kube-context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" \
    --namespace "$NAMESPACE" --wait --timeout 5m --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

revision() {
  helm status "$RELEASE" --kube-context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" \
    --namespace "$NAMESPACE" -o json | jq -er '.version'
}

status_map_for_revision() {
  printf '%s-platform-dependency-reconciler-status-r%s' "$RELEASE" "$1"
}

compatibility_map_for_revision() {
  printf '%s-remote-cluster-compatibility-r%s' "$RELEASE" "$1"
}

release_compatibility_map_for_revision() {
  printf '%s-release-compatibility-r%s' "$RELEASE" "$1"
}

helm upgrade --install "$RELEASE" "$ENVPLANE_CONFIGMAP_E2E_CHART_N_MINUS_1" \
  --kube-context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" --namespace "$NAMESPACE" --create-namespace \
  --values "$ENVPLANE_CONFIGMAP_E2E_VALUES_FILE" --server-side=true --wait --timeout 15m

# Simulate the exact safe observation write that used to make server-side Helm
# conflict with data.status.json. The payload has no credentials or provider
# configuration.
kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" apply --server-side \
  --field-manager=platform-reconciler -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${OLD_STATUS_MAP}
data:
  status.json: '{"schemaVersion":1,"generation":1,"observedAt":"2026-01-01T00:00:00Z","dependencies":{}}'
EOF

helm upgrade "$RELEASE" "$ENVPLANE_CONFIGMAP_E2E_CHART_N" \
  --kube-context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" --namespace "$NAMESPACE" \
  --values "$ENVPLANE_CONFIGMAP_E2E_VALUES_FILE" --server-side=true --wait --timeout 15m

current_revision="$(revision)"
current_status_map="$(status_map_for_revision "$current_revision")"
current_compatibility_map="$(compatibility_map_for_revision "$current_revision")"
current_release_compatibility_map="$(release_compatibility_map_for_revision "$current_revision")"
kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$current_status_map" >/dev/null
kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$current_compatibility_map" \
  -o json | jq -e '.immutable == true and (.data["release.json"] | type == "string" and length > 0)' >/dev/null
kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$current_release_compatibility_map" \
  -o json | jq -e '.immutable == true and (.data["release.json"] | type == "string" and length > 0)' >/dev/null
! kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$OLD_STATUS_MAP" >/dev/null 2>&1
! kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$OLD_COMPATIBILITY_MAP" >/dev/null 2>&1

# Rollback recreates the predecessor's immutable input instead of mutating the
# candidate map. The release remains usable without conflict overrides or manual deletion.
helm rollback "$RELEASE" 1 --kube-context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" \
  --namespace "$NAMESPACE" --server-side=true --wait --timeout 15m
kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$OLD_COMPATIBILITY_MAP" \
  -o json | jq -e '.immutable == true' >/dev/null
# The predecessor has no generic release map. Roll back to the current
# published revision as well, proving Helm restores its immutable map rather
# than mutating the newer map in place.
helm rollback "$RELEASE" "$current_revision" --kube-context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" \
  --namespace "$NAMESPACE" --server-side=true --wait --timeout 15m
kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$current_release_compatibility_map" \
  -o json | jq -e '.immutable == true' >/dev/null

helm uninstall "$RELEASE" --kube-context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" \
  --namespace "$NAMESPACE" --wait --timeout 5m
! kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$OLD_STATUS_MAP" >/dev/null 2>&1
! kubectl --context "$ENVPLANE_CONFIGMAP_E2E_CONTEXT" -n "$NAMESPACE" get configmap "$OLD_COMPATIBILITY_MAP" >/dev/null 2>&1
