#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deploy_root="$(cd "$script_dir/../.." && pwd)"
workflow="$deploy_root/.github/workflows/ci.yaml"

drift_line="$(grep -n 'scripts/check-vendored-chart-drift.sh' "$workflow" | head -n1 | cut -d: -f1)"
rebuild_line="$(grep -n 'scripts/lint-canonical-charts.sh' "$workflow" | head -n1 | cut -d: -f1)"
[[ -n "$drift_line" && -n "$rebuild_line" && "$drift_line" -lt "$rebuild_line" ]] || {
  echo "CI must check committed chart archives before rebuilding dependencies" >&2
  exit 1
}

grep -Fq 'helm dependency build --skip-refresh "$chart"' "$deploy_root/scripts/lint-canonical-charts.sh" || {
  echo "canonical chart lint must rebuild dependencies" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cp -a "$deploy_root" "$tmp_dir/deploy"
printf '\n# deliberately stale source fixture\n' >> "$tmp_dir/deploy/deploy/helm/envplane-agent/values.yaml"

set +e
output="$(cd "$tmp_dir/deploy" && bash scripts/check-vendored-chart-drift.sh 2>&1)"
status=$?
set -e
printf '%s\n' "$output"
[[ "$status" -ne 0 ]] || {
  echo "drift check accepted a stale vendored chart archive" >&2
  exit 1
}
grep -Eq 'vendored chart (metadata )?drift detected' <<<"$output" || {
  echo "drift check failed without identifying chart drift" >&2
  exit 1
}

echo "vendored chart drift regression test passed"
