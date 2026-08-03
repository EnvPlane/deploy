#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$root/.github/workflows/release-on-main.yaml"
resolver="$root/scripts/resolve-latest-published-artifacts.sh"

[[ -f "$workflow" ]] || { echo "main release workflow is missing" >&2; exit 1; }
[[ -x "$resolver" ]] || { echo "artifact resolver is not executable" >&2; exit 1; }
bash -n "$resolver"

for required in \
  "workflow_run:" \
  "Publish deploy image and charts (main)" \
  "workflow_run.conclusion" \
  "actions/download-artifact@v4" \
  "envpilot-compatible-artifacts" \
  "artifact_run_id" \
  "oras-project/setup-oras@v1" \
  "oras login ghcr.io" \
  "helm dependency build" \
  "helm package" \
  "helm push" \
  "cosign attest" \
  "gh release create"; do
  grep -Fq "$required" "$workflow" || { echo "workflow missing: $required" >&2; exit 1; }
done

if grep -Eq '^  push:' "$workflow"; then
  echo "umbrella release must not run directly on push" >&2
  exit 1
fi

grep -Fq "canonical source version" "$resolver" || {
  echo "resolver must have a verified source-version fallback for private package listings" >&2
  exit 1
}

grep -Fq 'sourceRevision:$sourceRevision' "$resolver" || {
  echo "artifact resolver must bind the report to the source revision" >&2
  exit 1
}

grep -Fq 'Select the artifact source revision' "$workflow" || {
  echo "release must checkout the artifact workflow source revision" >&2
  exit 1
}

grep -Fq 'Verify confirmed immutable artifacts' "$workflow" || {
  echo "release must validate the downloaded compatibility manifest" >&2
  exit 1
}

if grep -Fq 'Resolve latest published immutable artifacts' "$workflow"; then
  echo "release must consume the confirmed artifact manifest, not resolve independently" >&2
  exit 1
fi

grep -Fq 'controlPlane:control-plane' "$workflow" || {
  echo "workflow must map report controlPlane to the control-plane values component" >&2
  exit 1
}

grep -Fq '.charts[$component].version' "$workflow" || {
  echo "workflow must read child chart versions from the compatibility report" >&2
  exit 1
}

grep -Fq 'latest_published_umbrella' "$resolver" || {
  echo "resolver must verify the predecessor umbrella exists in OCI" >&2
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
