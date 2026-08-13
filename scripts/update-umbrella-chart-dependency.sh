#!/usr/bin/env bash
set -euo pipefail
component=""
version=""
chart_file="deploy/helm/envpilot/Chart.yaml"
values_file="deploy/helm/envpilot/values.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --component) component="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --chart-file) chart_file="${2:-}"; shift 2 ;;
    --values-file) values_file="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$component" in
  control-plane) dependency="envpilot-control-plane" ;;
  frontend) dependency="envpilot-frontend" ;;
  agent) dependency="envpilot-agent" ;;
  runner) dependency="envpilot-runner" ;;
  webhook) dependency="envpilot-webhook" ;;
  e2e-workload) dependency="envpilot-e2e-workload" ;;
  *) echo "unsupported component: $component" >&2; exit 2 ;;
esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || { echo "invalid chart version" >&2; exit 2; }
[[ -f "$chart_file" ]] || { echo "Chart.yaml not found: $chart_file" >&2; exit 2; }
tmp="$(mktemp "${chart_file}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
awk -v dependency="$dependency" -v version="$version" '
  $0 == "  - name: " dependency { in_dep=1; found=1 }
  in_dep && $0 ~ /^  - name:/ && $0 != "  - name: " dependency { in_dep=0 }
  in_dep && $0 ~ /^    version:/ { print "    version: " version; version_found=1; next }
  { print }
  END { if (!found || !version_found) exit 3 }
' "$chart_file" > "$tmp" || { echo "matching dependency/version field not found" >&2; exit 1; }
mv "$tmp" "$chart_file"
trap - EXIT
if [[ "$component" == "agent" ]]; then
  [[ -f "$values_file" ]] || { echo "values.yaml not found: $values_file" >&2; exit 2; }
  values_tmp="$(mktemp "${values_file}.XXXXXX")"
  trap 'rm -f "$values_tmp"' EXIT
  awk -v version="$version" '
    $0 == "  agentBootstrap:" { in_bootstrap=1 }
    in_bootstrap && $0 == "    chart:" { in_chart=1 }
    in_chart && $0 ~ /^    [^[:space:]]/ && $0 != "    chart:" { in_chart=0 }
    in_chart && $0 ~ /^      version:/ { print "      version: \"" version "\""; version_found=1; next }
    { print }
    END { if (!version_found) exit 3 }
  ' "$values_file" > "$values_tmp" || { echo "agentBootstrap.chart.version field not found" >&2; exit 1; }
  mv "$values_tmp" "$values_file"
  trap - EXIT
fi
if [[ "$component" == "e2e-workload" ]]; then
  [[ -f "$values_file" ]] || { echo "values.yaml not found: $values_file" >&2; exit 2; }
  values_tmp="$(mktemp "${values_file}.XXXXXX")"
  trap 'rm -f "$values_tmp"' EXIT
  awk -v version="$version" '
    $0 == "    bootstrapDefaults:" { in_defaults=1 }
    in_defaults && $0 ~ /^    [^[:space:]]/ && $0 != "    bootstrapDefaults:" { in_defaults=0 }
    in_defaults && $0 == "      helmDirect:" { in_helm_direct=1 }
    in_helm_direct && $0 ~ /^      [^[:space:]]/ && $0 != "      helmDirect:" { in_helm_direct=0 }
    in_helm_direct && $0 ~ /^        chartVersion:/ { print "        chartVersion: \"" version "\""; version_found=1; next }
    { print }
    END { if (!version_found) exit 3 }
  ' "$values_file" > "$values_tmp" || { echo "bootstrapDefaults.helmDirect.chartVersion field not found" >&2; exit 1; }
  mv "$values_tmp" "$values_file"
  trap - EXIT
fi
echo "updated umbrella dependency $dependency to $version"
