#!/usr/bin/env bash
set -euo pipefail
component=""
version=""
chart_file="deploy/helm/envpilot/Chart.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --component) component="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --chart-file) chart_file="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$component" in
  control-plane) dependency="envpilot-control-plane" ;;
  frontend) dependency="envpilot-frontend" ;;
  agent) dependency="envpilot-agent" ;;
  runner) dependency="envpilot-runner" ;;
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
echo "updated umbrella dependency $dependency to $version"
