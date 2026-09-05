#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_rendered="$(mktemp)"
single_rendered="$(mktemp)"
invalid_error="$(mktemp)"
trap 'rm -f "$default_rendered" "$single_rendered" "$invalid_error"' EXIT

helm template default "$chart_dir" \
  --set postgres.tls.enabled=false >"$default_rendered"
! rg -q '^kind: HorizontalPodAutoscaler$' "$default_rendered"

helm template single "$chart_dir" \
  --set postgres.tls.enabled=false \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=1 \
  --set autoscaling.maxReplicas=1 >"$single_rendered"
rg -Fq 'kind: HorizontalPodAutoscaler' "$single_rendered"
rg -Fq 'maxReplicas: 1' "$single_rendered"

set +e
helm template invalid "$chart_dir" \
  --set postgres.tls.enabled=false \
  --set autoscaling.enabled=true \
  --set autoscaling.maxReplicas=2 > /dev/null 2>"$invalid_error"
rc=$?
set -e
test "$rc" -ne 0
rg -Fq 'autoscaling is unsupported above one replica' "$invalid_error"

echo "control-plane single-replica autoscaling contract is valid"
