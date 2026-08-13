#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -R "$root/deploy/helm/envpilot" "$tmp/envpilot"
sed -i.bak 's/^version: 0.3.0$/version: 0.3.1/' "$tmp/envpilot/Chart.yaml"
rm -f "$tmp/envpilot/Chart.yaml.bak"
"$root/scripts/update-umbrella-chart-dependency.sh" --component runner --version 0.3.1 --chart-file "$tmp/envpilot/Chart.yaml" --values-file "$tmp/envpilot/values.yaml"
for dependency in envpilot-control-plane envpilot-frontend envpilot-agent envpilot-e2e-workload; do
  grep -A2 "name: $dependency" "$root/deploy/helm/envpilot/Chart.yaml" > "$tmp/before-$dependency"
  grep -A2 "name: $dependency" "$tmp/envpilot/Chart.yaml" > "$tmp/after-$dependency"
  cmp "$tmp/before-$dependency" "$tmp/after-$dependency"
done
grep -A2 'name: envpilot-runner' "$tmp/envpilot/Chart.yaml" | grep -q 'version: 0.3.1'
"$root/scripts/update-umbrella-chart-dependency.sh" --component agent --version 0.2.1 --chart-file "$tmp/envpilot/Chart.yaml" --values-file "$tmp/envpilot/values.yaml"
grep -A2 'name: envpilot-agent' "$tmp/envpilot/Chart.yaml" | grep -q 'version: 0.2.1'
awk '/  agentBootstrap:/{in_bootstrap=1} in_bootstrap&&/    chart:/{in_chart=1} in_chart&&/      version:/{print; exit}' "$tmp/envpilot/values.yaml" | grep -q 'version: "0.2.1"'
"$root/scripts/update-umbrella-chart-dependency.sh" --component e2e-workload --version 0.1.1 --chart-file "$tmp/envpilot/Chart.yaml" --values-file "$tmp/envpilot/values.yaml"
grep -A2 'name: envpilot-e2e-workload' "$tmp/envpilot/Chart.yaml" | grep -q 'version: 0.1.1'
grep -A2 '^    bootstrapDefaults:' "$tmp/envpilot/values.yaml" | grep -q 'chartVersion: "0.1.1"'
echo "umbrella dependency isolation test passed"
