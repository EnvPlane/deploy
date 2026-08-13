#!/usr/bin/env bash
# Immutable OCI chart versions must describe immutable chart source. Refuse a
# publish if a child chart's rendered source changed without a SemVer bump;
# otherwise a later umbrella can silently select stale chart content.
set -euo pipefail

base=""
head="HEAD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) base="${2:-}"; shift 2 ;;
    --head) head="${2:-}"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --base <revision> [--head <revision>]" >&2
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$base" ]] || { echo "--base is required" >&2; exit 2; }
git rev-parse --verify --quiet "${base}^{commit}" >/dev/null || { echo "invalid base revision" >&2; exit 2; }
git rev-parse --verify --quiet "${head}^{commit}" >/dev/null || { echo "invalid head revision" >&2; exit 2; }

chart_version_at() {
  local revision="$1"
  local chart_dir="$2"
  git show "$revision:$chart_dir/Chart.yaml" | sed -n 's/^version: //p' | head -n 1
}

for chart in \
  envpilot-control-plane \
  envpilot-frontend \
  envpilot-agent \
  envpilot-runner \
  envpilot-webhook \
  envpilot-e2e-workload; do
  chart_dir="deploy/helm/$chart"
  changed="$(git diff --name-only "$base" "$head" -- "$chart_dir")"
  [[ -n "$changed" ]] || continue

  # Tests, documentation and vendored build output do not alter the OCI chart.
  # Keep this guard self-contained: publish runners guarantee grep, unlike
  # optional developer tools such as ripgrep. A non-match is expected; a
  # missing matcher must fail rather than silently disable enforcement.
  if source_changed="$(printf '%s\n' "$changed" | grep -E "^${chart_dir}/(Chart\\.yaml|values\\.yaml|templates/|crds/|files/)")"; then
    :
  else
    matcher_status=$?
    [[ "$matcher_status" -eq 1 ]] || exit "$matcher_status"
    source_changed=""
  fi
  [[ -n "$source_changed" ]] || continue

  before_version="$(chart_version_at "$base" "$chart_dir")"
  after_version="$(chart_version_at "$head" "$chart_dir")"

  [[ "$after_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "invalid version for changed child chart $chart: $after_version" >&2
    exit 1
  }
  if [[ "$before_version" == "$after_version" ]]; then
    echo "changed child chart $chart must bump version (still $after_version)" >&2
    exit 1
  fi
done
