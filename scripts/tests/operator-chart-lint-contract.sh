#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
chart="$root/deploy/helm/envplane-finops-private"
report="$(mktemp)"
trap 'rm -f "$report"' EXIT
if helm lint "$chart" >"$report" 2>&1; then
  echo "operator-only chart unexpectedly accepts blank required settings" >&2
  exit 1
fi
grep -q exporters "$report"
helm lint "$chart" -f "$root/scripts/fixtures/finops-private-lint.yaml"
echo "operator-only chart lint profile contract passed"
