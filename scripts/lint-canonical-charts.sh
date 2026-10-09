#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for chart in "$root"/deploy/helm/*; do
  [[ -f "$chart/Chart.yaml" ]] || continue
  helm dependency build --skip-refresh "$chart"
  if [[ "$(basename "$chart")" == "envplane-finops-private" ]]; then
    # This operator-only chart deliberately has no deployable default profile.
    # Supply render-only data without weakening its required-value schema.
    helm lint "$chart" -f "$root/scripts/fixtures/finops-private-lint.yaml"
  else
    helm lint "$chart"
  fi
done
