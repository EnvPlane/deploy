#!/usr/bin/env bash
set -euo pipefail

# Runs against an already-provisioned cluster. It verifies the lifecycle of
# EnvPlane-owned reconciler support objects, while proving that the operator's
# registry Secret and existing ingress provider survive uninstall/reinstall.
: "${PLATFORM_RECONCILER_LIFECYCLE_CONTEXT:?set the Kubernetes context}"
: "${PLATFORM_RECONCILER_LIFECYCLE_REGISTRY_SECRET:?set an existing image-pull Secret name}"
: "${PLATFORM_RECONCILER_LIFECYCLE_INGRESS_CLASS:=nginx}"

NAMESPACE="${PLATFORM_RECONCILER_LIFECYCLE_NAMESPACE:-envplane-e2e-lifecycle}"
RELEASE="${PLATFORM_RECONCILER_LIFECYCLE_RELEASE:-envplane-lifecycle-e2e}"
CHART="${PLATFORM_RECONCILER_LIFECYCLE_CHART:-./deploy/helm/envplane}"
STATUS_CONFIG_MAP=""

helm_args=(
  --kube-context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT"
  --namespace "$NAMESPACE"
  --create-namespace
  --set platformDependencyReconciler.enabled=true
  --set platformDependencies.ingress.mode=existing
  --set platformDependencies.ingress.provider=nginx
  --set "platformDependencies.ingress.existingClassName=$PLATFORM_RECONCILER_LIFECYCLE_INGRESS_CLASS"
  --set global.envplane.registry.mode=existing
  --set "global.envplane.registry.existingSecret=$PLATFORM_RECONCILER_LIFECYCLE_REGISTRY_SECRET"
)

cleanup() {
  helm uninstall "$RELEASE" --kube-context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" \
    --namespace "$NAMESPACE" --wait --timeout 3m --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

registry_uid="$(kubectl --context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" -n "$NAMESPACE" get secret "$PLATFORM_RECONCILER_LIFECYCLE_REGISTRY_SECRET" -o jsonpath='{.metadata.uid}')"
ingress_uid="$(kubectl --context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" get ingressclass "$PLATFORM_RECONCILER_LIFECYCLE_INGRESS_CLASS" -o jsonpath='{.metadata.uid}')"
test -n "$registry_uid"
test -n "$ingress_uid"

assert_owned_support_exists() {
  local revision status_config_map
  revision="$(helm status "$RELEASE" --kube-context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" --namespace "$NAMESPACE" -o json | jq -r '.version')"
  status_config_map="${RELEASE}-platform-dependency-reconciler-status-r${revision}"
  STATUS_CONFIG_MAP="$status_config_map"
  for object in \
    "configmap/$RELEASE-platform-dependency-reconciler" \
    "configmap/$status_config_map" \
    "serviceaccount/$RELEASE-platform-reconciler" \
    "role/$RELEASE-platform-reconciler-status" \
    "rolebinding/$RELEASE-platform-reconciler-status"; do
    kubectl --context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" -n "$NAMESPACE" get "$object" >/dev/null
  done
  for object in \
    "clusterrole/$RELEASE-platform-reconciler-discovery" \
    "clusterrolebinding/$RELEASE-platform-reconciler-discovery"; do
    kubectl --context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" get "$object" >/dev/null
  done
}

assert_owned_support_absent() {
  test -n "$STATUS_CONFIG_MAP"
  for object in \
    "configmap/$RELEASE-platform-dependency-reconciler" \
    "configmap/$STATUS_CONFIG_MAP" \
    "serviceaccount/$RELEASE-platform-reconciler" \
    "role/$RELEASE-platform-reconciler-status" \
    "rolebinding/$RELEASE-platform-reconciler-status"; do
    ! kubectl --context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" -n "$NAMESPACE" get "$object" >/dev/null 2>&1
  done
  for object in \
    "clusterrole/$RELEASE-platform-reconciler-discovery" \
    "clusterrolebinding/$RELEASE-platform-reconciler-discovery"; do
    ! kubectl --context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" get "$object" >/dev/null 2>&1
  done
}

helm upgrade --install "$RELEASE" "$CHART" "${helm_args[@]}" --wait --timeout 10m
assert_owned_support_exists
helm uninstall "$RELEASE" --kube-context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" --namespace "$NAMESPACE" --wait --timeout 3m
assert_owned_support_absent

# Neither external object was part of the release and neither may be adopted or
# removed by the reconciler cleanup hook.
test "$(kubectl --context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" -n "$NAMESPACE" get secret "$PLATFORM_RECONCILER_LIFECYCLE_REGISTRY_SECRET" -o jsonpath='{.metadata.uid}')" = "$registry_uid"
test "$(kubectl --context "$PLATFORM_RECONCILER_LIFECYCLE_CONTEXT" get ingressclass "$PLATFORM_RECONCILER_LIFECYCLE_INGRESS_CLASS" -o jsonpath='{.metadata.uid}')" = "$ingress_uid"

# A clean reinstall must not need manual deletion of stale support objects.
helm upgrade --install "$RELEASE" "$CHART" "${helm_args[@]}" --wait --timeout 10m
assert_owned_support_exists
