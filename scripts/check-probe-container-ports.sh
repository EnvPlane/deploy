#!/usr/bin/env bash
set -euo pipefail

chart_dir="${1:-}"
if [[ -z "$chart_dir" || ! -f "$chart_dir/Chart.yaml" ]]; then
  echo "usage: $0 CHART_DIR" >&2
  exit 2
fi

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
helm template probe-port-check "$chart_dir" >"$rendered"

declare -A declared_ports=()
while IFS=$'\t' read -r deployment container port; do
  [[ -n "$deployment" ]] || continue
  declared_ports["$deployment/$container/$port"]=1
done < <(yq -r '
  select(.kind == "Deployment")
  | .metadata.name as $deployment
  | (.spec.template.spec.containers // [])[]
  | .name as $container
  | (.ports // [])[]
  | [$deployment, $container, (.containerPort | tostring)] | join("\t")
' "$rendered")

while IFS=$'\t' read -r deployment container port; do
  [[ -n "$deployment" ]] || continue
  if [[ -z "${declared_ports["$deployment/$container/$port"]:-}" ]]; then
    echo "$deployment/$container: probe port $port is not declared as a containerPort" >&2
    exit 1
  fi
done < <(yq -r '
  select(.kind == "Deployment")
  | .metadata.name as $deployment
  | (.spec.template.spec.containers // [])[]
  | .name as $container
  | [.livenessProbe.tcpSocket.port, .readinessProbe.tcpSocket.port][]
  | select(. != null)
  | [$deployment, $container, (tostring)] | join("\t")
' "$rendered")
