#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$root/.github/workflows/release-on-main.yaml"
resolver="$root/scripts/resolve-latest-published-artifacts.sh"

[[ -f "$workflow" ]] || { echo "main release workflow is missing" >&2; exit 1; }
[[ -x "$resolver" ]] || { echo "artifact resolver is not executable" >&2; exit 1; }
bash -n "$resolver"

for required in \
  "branches: [main]" \
  "resolve-latest-published-artifacts.sh" \
  "oras-project/setup-oras@v1" \
  "oras login ghcr.io" \
  "helm dependency build" \
  "helm package" \
  "helm push" \
  "cosign attest" \
  "gh release create"; do
  grep -Fq "$required" "$workflow" || { echo "workflow missing: $required" >&2; exit 1; }
done

grep -Fq "canonical source version" "$resolver" || {
  echo "resolver must have a verified source-version fallback for private package listings" >&2
  exit 1
}

grep -Fq 'controlPlane:control-plane' "$workflow" || {
  echo "workflow must map report controlPlane to the control-plane values component" >&2
  exit 1
}

for required in \
  "ghcr.io/envpilot/api" \
  "ghcr.io/envpilot/frontend" \
  "ghcr.io/envpilot/agent" \
  "ghcr.io/envpilot/runner" \
  "ghcr.io/envpilot/platform-reconciler"; do
  grep -Fq "$required" "$resolver" || { echo "resolver missing: $required" >&2; exit 1; }
done

if grep -Eq ':[[:space:]]*(latest|main)([[:space:]"'"'"'@]|$)|tag:[[:space:]]*(latest|main)([[:space:]"'"'"'@]|$)' "$workflow"; then
  echo "automatic umbrella releases must not use mutable latest/main refs" >&2
  exit 1
fi

echo "release-on-main workflow contract is valid"
