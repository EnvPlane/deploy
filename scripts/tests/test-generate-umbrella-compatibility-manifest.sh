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
  ' "$root/deploy/helm/envplane/Chart.yaml"
}

jq -n \
  --arg revision "$revision" \
  --arg controlPlaneVersion "$(version_for envplane-control-plane)" \
  --arg frontendVersion "$(version_for envplane-frontend)" \
  --arg agentVersion "$(version_for envplane-agent)" \
  --arg runnerVersion "$(version_for envplane-runner)" \
  --arg webhookVersion "$(version_for envplane-webhook)" \
  --arg e2eWorkloadVersion "$(version_for envplane-e2e-workload)" \
  '{schemaVersion:1,sourceRevision:$revision,charts:{
    controlPlane:{repository:"oci://ghcr.io/envplane/envplane-control-plane",version:$controlPlaneVersion,digest:("sha256:" + ("1" * 64)),sourceRevision:$revision},
    frontend:{repository:"oci://ghcr.io/envplane/envplane-frontend",version:$frontendVersion,digest:("sha256:" + ("2" * 64)),sourceRevision:$revision},
    agent:{repository:"oci://ghcr.io/envplane/envplane-agent",version:$agentVersion,digest:("sha256:" + ("3" * 64)),sourceRevision:$revision},
    runner:{repository:"oci://ghcr.io/envplane/envplane-runner",version:$runnerVersion,digest:("sha256:" + ("4" * 64)),sourceRevision:$revision},
    webhook:{repository:"oci://ghcr.io/envplane/envplane-webhook",version:$webhookVersion,digest:("sha256:" + ("5" * 64)),sourceRevision:$revision},
    e2eWorkload:{repository:"oci://ghcr.io/envplane/envplane-e2e-workload",version:$e2eWorkloadVersion,digest:("sha256:" + ("6" * 64)),sourceRevision:$revision}
  }}' > "$tmp/artifacts.json"

"$root/scripts/generate-umbrella-compatibility-manifest.sh" \
  --version 9.9.9 \
  --source-revision "$revision" \
  --values-file "$root/deploy/helm/envplane/values.yaml" \
  --chart-file "$root/deploy/helm/envplane/Chart.yaml" \
  --artifact-report "$tmp/artifacts.json" \
  --output "$tmp/release.json" >/dev/null

jq -e '(.images | length == 6) and (.childCharts | length == 6) and all((.images + .childCharts)[]; (.digest | test("^sha256:[0-9a-f]{64}$")) and .attestations.sbom.required == true and .attestations.provenance.required == true) and all(.childCharts[]; (.sourceRevision | test("^[0-9a-f]{40}$")))' "$tmp/release.json" >/dev/null

echo "immutable child-chart compatibility manifest regression is valid"
