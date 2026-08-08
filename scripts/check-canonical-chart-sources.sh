#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: check-canonical-chart-sources.sh --deploy <path> [--runner <path>] [--control-plane <path>] [--frontend <path>] [--agent <path>] [--webhook <path>]
EOF
  exit 2
}

deploy_root=""
declare_paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy|--runner|--control-plane|--frontend|--agent|--webhook)
      [[ $# -ge 2 ]] || usage
      declare_paths+=("${1#--}=$2")
      [[ "$1" == "--deploy" ]] && deploy_root="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ -n "$deploy_root" && -d "$deploy_root/deploy/helm" ]] || usage

canonical_root="$deploy_root/deploy/helm"
core_names=$'envpilot-control-plane\nenvpilot-frontend\nenvpilot-agent\nenvpilot-runner\nenvpilot-webhook'
expected_names=$'envpilot-control-plane\nenvpilot-frontend\nenvpilot-agent\nenvpilot-runner\nenvpilot-webhook'

contains_line() {
  local values="$1"
  local needle="$2"
  grep -Fxq "$needle" <<<"$values"
}

for expected in $expected_names; do
  chart="$canonical_root/$expected/Chart.yaml"
  [[ -f "$chart" ]] || { echo "canonical chart is missing: $chart" >&2; exit 1; }
  actual="$(awk -F': ' '$1 == "name" {print $2; exit}' "$chart")"
  [[ "$actual" == "$expected" ]] || {
    echo "canonical chart name mismatch in $chart: expected $expected, got $actual" >&2
    exit 1
  }
done

chart_entries="$(mktemp)"
trap 'rm -f "$chart_entries"' EXIT

for item in "${declare_paths[@]}"; do
  name="${item%%=*}"
  root="${item#*=}"
  [[ -d "$root" ]] || continue
  if [[ "$root" == "$deploy_root" ]]; then
    chart_files=(find "$root" -path '*/.git' -prune -o -name Chart.yaml -type f -print)
  else
    chart_files=(find "$root" -path '*/.git' -prune -o -path "$deploy_root" -prune -o -name Chart.yaml -type f -print)
  fi
  while IFS= read -r chart; do
    chart_name="$(awk -F': ' '$1 == "name" {print $2; exit}' "$chart")"
    [[ -n "$chart_name" ]] || { echo "Chart.yaml without name: $chart" >&2; exit 1; }
    printf '%s\t%s\t%s\n' "$chart_name" "$name" "$chart" >>"$chart_entries"

    if [[ "$chart" == "$canonical_root/"* ]]; then
      continue
    fi
    # This runtime-bundled fixture is intentionally not published as a component
    # chart. Its removal is tracked separately from this source consolidation.
    if [[ "$name" == "control-plane" && "$chart_name" == "envpilot-smoke" && "$chart" == "$root/charts/envpilot-smoke/Chart.yaml" ]]; then
      continue
    fi
    if contains_line "$core_names" "$chart_name"; then
      echo "duplicate core chart source outside deploy: $chart" >&2
      exit 1
    fi
    echo "non-canonical EnvPilot chart source outside deploy: $chart" >&2
    exit 1
  done < <("${chart_files[@]}" | sort)
done

while IFS=$'\t' read -r chart_name _first_root first_path; do
  count="$(awk -F '\t' -v name="$chart_name" '$1 == name {count++} END {print count + 0}' "$chart_entries")"
  if (( count > 1 )); then
    echo "duplicate chart name $chart_name includes $first_path" >&2
    awk -F '\t' -v name="$chart_name" '$1 == name {print "  " $3}' "$chart_entries" >&2
    exit 1
  fi
done < <(sort -u -t $'\t' -k1,1 "$chart_entries")

echo "canonical Helm chart source check passed"
