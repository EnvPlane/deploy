#!/usr/bin/env bash
# Render-only guard for the management-cluster Secret boundary. Runtime API
# tests cover kubeconfig/TLS; this guard prevents an accidental RBAC expansion.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
chart="$root/deploy/helm/envpilot-control-plane"
rendered="$(mktemp "${TMPDIR:-/tmp}/envpilot-remote-credentials.XXXXXX")"
trap 'rm -f "$rendered"' EXIT

helm template envpilot "$chart" --namespace envpilot \
  --set rbac.remoteClusterCredentials.enabled=true \
  --set-string postgres.auth.password=ci-render-only-password \
  --set postgres.tls.enabled=false > "$rendered"

grep -Fq -- '-remote-cluster-credentials' "$rendered"
grep -Fq 'verbs: ["get", "create", "update", "patch"]' "$rendered"
if grep -A12 -- '-remote-cluster-credentials' "$rendered" | grep -Eq 'clusterroles|configmaps|\["\*"\]'; then
  echo 'remote credential RBAC must remain namespace-scoped and Secret-only' >&2
  exit 1
fi

disabled="$(mktemp "${TMPDIR:-/tmp}/envpilot-remote-credentials-disabled.XXXXXX")"
trap 'rm -f "$rendered" "$disabled"' EXIT
helm template envpilot "$chart" --namespace envpilot \
  --set-string postgres.auth.password=ci-render-only-password \
  --set postgres.tls.enabled=false > "$disabled"
if grep -Fq -- '-remote-cluster-credentials' "$disabled"; then
  echo 'remote credential writer RBAC must remain opt-in' >&2
  exit 1
fi

echo 'remote cluster credential RBAC contract is valid'
