#!/usr/bin/env bash
set -euo pipefail

: "${PLATFORM_E2E_CONTEXT:?set a comma-separated list of kube contexts}"
NAMESPACE="${PLATFORM_E2E_NAMESPACE:-envpilot-e2e-platform}"
RELEASE="${PLATFORM_E2E_RELEASE:-envpilot-platform-e2e}"
CHART="${PLATFORM_E2E_CHART:-./deploy/helm/envpilot}"
MATRIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/platform-dependencies"

IFS=',' read -r -a contexts <<< "$PLATFORM_E2E_CONTEXT"
for context in "${contexts[@]}"; do
  for scenario in empty existing mixed degraded; do
    values="$MATRIX_DIR/$scenario.yaml"
    echo "==> context=$context scenario=$scenario"
    if [[ "$scenario" == degraded ]]; then
      set +e
      helm upgrade --install "$RELEASE" "$CHART" --kube-context "$context" \
        --namespace "$NAMESPACE" --create-namespace --values "$values" --wait --timeout 10m
      rc=$?
      set -e
      test "$rc" -ne 0
    else
      helm upgrade --install "$RELEASE" "$CHART" --kube-context "$context" \
        --namespace "$NAMESPACE" --create-namespace --values "$values" --wait --timeout 10m
    fi
    status="$(kubectl --context "$context" -n "$NAMESPACE" get configmap "${RELEASE}-platform-dependency-reconciler-status" -o jsonpath='{.data.status\.json}')"
    test -n "$status"
    printf '%s\n' "$status" | jq -e 'type == "object" and has("ingress") and has("dns") and has("storage")' >/dev/null

    # Reinstalling healthy scenarios must be idempotent. The degraded case is
    # expected to remain blocked with the same actionable diagnostic.
    if [[ "$scenario" != degraded ]]; then
      helm upgrade --install "$RELEASE" "$CHART" --kube-context "$context" \
        --namespace "$NAMESPACE" --values "$values" --wait --timeout 10m >/dev/null
    fi

    helm uninstall "$RELEASE" --kube-context "$context" --namespace "$NAMESPACE" --wait
    # Detected/external resources must survive uninstall; managed resources are
    # removed according to cleanupPolicy by the pre-delete hook.
  done
done
