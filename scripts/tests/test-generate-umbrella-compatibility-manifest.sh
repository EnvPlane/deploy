#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
revision="0123456789abcdef0123456789abcdef01234567"

version_for() {
  local name="$1"
  awk -v name="$name" '
    $0 == "  - name: " name { in_dependency=1; next }
    in_dependency && /^  - name: / { exit }
    in_dependency && /^    version: / { print $2; exit }
  ' "$root/deploy/helm/envpilot/Chart.yaml"
}

jq -n \
  --arg revision "$revision" \
  --arg controlPlaneVersion "$(version_for envpilot-control-plane)" \
  --arg frontendVersion "$(version_for envpilot-frontend)" \
  --arg agentVersion "$(version_for envpilot-agent)" \
  --arg runnerVersion "$(version_for envpilot-runner)" \
  --arg webhookVersion "$(version_for envpilot-webhook)" \
  '{schemaVersion:1,sourceRevision:$revision,charts:{
    controlPlane:{repository:"oci://ghcr.io/envpilot/envpilot-control-plane",version:$controlPlaneVersion,digest:("sha256:" + ("1" * 64)),sourceRevision:$revision},
    frontend:{repository:"oci://ghcr.io/envpilot/envpilot-frontend",version:$frontendVersion,digest:("sha256:" + ("2" * 64)),sourceRevision:$revision},
    agent:{repository:"oci://ghcr.io/envpilot/envpilot-agent",version:$agentVersion,digest:("sha256:" + ("3" * 64)),sourceRevision:$revision},
    runner:{repository:"oci://ghcr.io/envpilot/envpilot-runner",version:$runnerVersion,digest:("sha256:" + ("4" * 64)),sourceRevision:$revision},
    webhook:{repository:"oci://ghcr.io/envpilot/envpilot-webhook",version:$webhookVersion,digest:("sha256:" + ("5" * 64)),sourceRevision:$revision}
  }}' > "$tmp/artifacts.json"

"$root/scripts/generate-umbrella-compatibility-manifest.sh" \
  --version 9.9.9 \
  --source-revision "$revision" \
  --values-file "$root/deploy/helm/envpilot/values.yaml" \
  --chart-file "$root/deploy/helm/envpilot/Chart.yaml" \
  --artifact-report "$tmp/artifacts.json" \
  --output "$tmp/release.json" >/dev/null

jq -e '(.childCharts | length == 5) and all(.childCharts[]; (.digest | test("^sha256:[0-9a-f]{64}$")) and (.sourceRevision | test("^[0-9a-f]{40}$")))' "$tmp/release.json" >/dev/null

echo "immutable child-chart compatibility manifest regression is valid"
