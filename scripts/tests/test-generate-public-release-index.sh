#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

version="1.2.3"
digest="sha256:$(printf 'a%.0s' {1..64})"
revision="$(printf 'b%.0s' {1..40})"
"$root/scripts/generate-public-release-index.sh" \
  --version "$version" --digest "$digest" --source-revision "$revision" \
  --output "$tmp/index.json"

jq -e --arg version "$version" --arg digest "$digest" '
  .version == $version and .chart.digest == $digest and
  .support.clusterTargets == ["current", "remote"] and
  .support.deploymentModes == ["cloud", "on-prem"] and
  (.status.commands | length) == 3 and
  .firstRun.screen == "initial-authentication" and
  (.install.command == ("helm upgrade --install envplane " + .chart.repository + " --version " + $version + " --namespace envplane --create-namespace --wait"))
' "$tmp/index.json" >/dev/null
! rg -qi 'kubeconfig|credential|scm.?token|secret' "$tmp/index.json"

echo "public release index contract passed"
