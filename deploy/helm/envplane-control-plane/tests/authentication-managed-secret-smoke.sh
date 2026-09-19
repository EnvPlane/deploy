#!/usr/bin/env bash
# Verifies the default authentication-managed Secret wiring against a real
# cluster. It is intentionally opt-in so chart unit tests never mutate a
# developer's current context.
set -euo pipefail

: "${AUTH_MANAGED_SECRET_SMOKE_CONTEXT:?set a disposable Kubernetes context}"

chart="${AUTH_MANAGED_SECRET_SMOKE_CHART:-../}"
release="${AUTH_MANAGED_SECRET_SMOKE_RELEASE:-envplane-auth-smoke}"
namespace="${AUTH_MANAGED_SECRET_SMOKE_NAMESPACE:-envplane-auth-smoke}"
created_namespace=false

cleanup() {
  if [[ "$created_namespace" == true ]]; then
    kubectl --context "$AUTH_MANAGED_SECRET_SMOKE_CONTEXT" delete namespace "$namespace" --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! kubectl --context "$AUTH_MANAGED_SECRET_SMOKE_CONTEXT" get namespace "$namespace" >/dev/null 2>&1; then
  created_namespace=true
fi

# The second invocation exercises the upgrade path. No auth values or
# credential Secret are supplied: the chart must render the empty managed
# container, its exact-name RBAC, and the API environment identifier.
for invocation in install upgrade; do
  helm upgrade --install "$release" "$chart" \
    --kube-context "$AUTH_MANAGED_SECRET_SMOKE_CONTEXT" \
    --namespace "$namespace" --create-namespace --wait --timeout 10m
done

deployment="envplane-control-plane"
secret="${deployment}-authentication"
kubectl --context "$AUTH_MANAGED_SECRET_SMOKE_CONTEXT" --namespace "$namespace" rollout status "deployment/$deployment" --timeout=5m
test "$(kubectl --context "$AUTH_MANAGED_SECRET_SMOKE_CONTEXT" --namespace "$namespace" get secret "$secret" -o jsonpath='{.type}')" = Opaque
test -z "$(kubectl --context "$AUTH_MANAGED_SECRET_SMOKE_CONTEXT" --namespace "$namespace" get secret "$secret" -o jsonpath='{.data}')"
test "$(kubectl --context "$AUTH_MANAGED_SECRET_SMOKE_CONTEXT" --namespace "$namespace" get role "${deployment}-authentication-managed-secret" -o jsonpath='{.rules[0].resourceNames[0]}')" = "$secret"
test "$(kubectl --context "$AUTH_MANAGED_SECRET_SMOKE_CONTEXT" --namespace "$namespace" get deployment "$deployment" -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].env[?(@.name=="ENVPLANE_AUTHENTICATION_MANAGED_SECRET_NAME")].value}')" = "$secret"
