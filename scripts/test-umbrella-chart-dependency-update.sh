#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -R "$root/deploy/helm/envplane" "$tmp/envplane"
sed -i.bak 's/^version: 0.3.0$/version: 0.3.1/' "$tmp/envplane/Chart.yaml"
rm -f "$tmp/envplane/Chart.yaml.bak"
"$root/scripts/update-umbrella-chart-dependency.sh" --component runner --version 0.3.1 --chart-file "$tmp/envplane/Chart.yaml" --values-file "$tmp/envplane/values.yaml"
for dependency in envplane-control-plane envplane-frontend envplane-agent envplane-e2e-workload; do
  grep -A2 "name: $dependency" "$root/deploy/helm/envplane/Chart.yaml" > "$tmp/before-$dependency"
  grep -A2 "name: $dependency" "$tmp/envplane/Chart.yaml" > "$tmp/after-$dependency"
  cmp "$tmp/before-$dependency" "$tmp/after-$dependency"
done
grep -A2 'name: envplane-runner' "$tmp/envplane/Chart.yaml" | grep -q 'version: 0.3.1'
"$root/scripts/update-umbrella-chart-dependency.sh" --component agent --version 0.2.1 --chart-file "$tmp/envplane/Chart.yaml" --values-file "$tmp/envplane/values.yaml"
grep -A2 'name: envplane-agent' "$tmp/envplane/Chart.yaml" | grep -q 'version: 0.2.1'
awk '/  agentBootstrap:/{in_bootstrap=1} in_bootstrap&&/    chart:/{in_chart=1} in_chart&&/      version:/{print; exit}' "$tmp/envplane/values.yaml" | grep -q 'version: "0.2.1"'
"$root/scripts/update-umbrella-chart-dependency.sh" --component e2e-workload --version 0.1.1 --chart-file "$tmp/envplane/Chart.yaml" --values-file "$tmp/envplane/values.yaml"
grep -A2 'name: envplane-e2e-workload' "$tmp/envplane/Chart.yaml" | grep -q 'version: 0.1.1'
grep -A3 '^    bootstrapDefaults:' "$tmp/envplane/values.yaml" | grep -q '^      helmDirect:$'
grep -A3 '^    bootstrapDefaults:' "$tmp/envplane/values.yaml" | grep -q 'chartVersion: "0.1.1"'
"$root/scripts/update-umbrella-chart-dependency.sh" --component e2e-workload --version 0.1.0 --chart-file "$tmp/envplane/Chart.yaml" --values-file "$tmp/envplane/values.yaml" >/dev/null
helm template envplane "$tmp/envplane" \
  --set envplane-control-plane.postgres.auth.password=test-password \
  --set envplane-control-plane.postgres.tls.enabled=false \
  | grep -q 'ENVPLANE_BOOTSTRAP_DEFAULT_HELM_DIRECT_CHART_REF'
echo "umbrella dependency isolation test passed"
