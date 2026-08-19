#!/usr/bin/env bash
set -euo pipefail
component=""; chart=""; version=""; digest=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --component) component="${2:-}"; shift 2 ;;
    --chart) chart="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --digest) digest="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "${GH_TOKEN:-}" ]] || { echo "GH_TOKEN is required" >&2; exit 2; }
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "invalid digest" >&2; exit 2; }
payload="$(jq -cn --arg component "$component" --arg chart "$chart" --arg version "$version" --arg digest "$digest" --arg source_repository "EnvPlane/deploy" --arg source_revision "$GITHUB_SHA" '{component:$component,chart:$chart,version:$version,repository:("oci://ghcr.io/EnvPlane/" + $chart),digest:$digest,source_repository:$source_repository,source_revision:$source_revision,publication_id:($component + ":" + $source_revision + ":" + $digest)}')"
curl --fail-with-body --silent --show-error \
  --connect-timeout 10 --max-time 30 \
  --retry 6 --retry-delay 5 --retry-max-time 120 \
  --request POST \
  --url "https://api.github.com/repos/EnvPlane/deploy/dispatches" \
  --header "Accept: application/vnd.github+json" \
  --header "Authorization: Bearer $GH_TOKEN" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  --data "$(jq -cn --argjson payload "$payload" '{event_type:"component-chart-published",client_payload:$payload}')"
