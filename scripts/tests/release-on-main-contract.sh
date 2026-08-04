#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$root/.github/workflows/release-on-main.yaml"
artifact_workflow="$root/.github/workflows/publish-main.yaml"
resolver="$root/scripts/resolve-latest-published-artifacts.sh"
child_publisher="$root/scripts/publish-selected-child-charts.sh"

[[ -f "$workflow" ]] || { echo "main release workflow is missing" >&2; exit 1; }
[[ -x "$resolver" ]] || { echo "artifact resolver is not executable" >&2; exit 1; }
[[ -x "$child_publisher" ]] || { echo "selected child-chart publisher is not executable" >&2; exit 1; }
bash -n "$resolver"
bash -n "$child_publisher"

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

grep -Fq "pinned source tree" "$resolver" || {
  echo "resolver must verify pinned source artifacts rather than selecting registry latest" >&2
  exit 1
}

grep -Fq -- "--values-file" "$artifact_workflow" || {
  echo "artifact workflow must resolve the image refs committed in values.yaml" >&2
  exit 1
}

grep -Fq 'Publish selected stable child charts' "$artifact_workflow" || {
  echo "artifact workflow must publish selected stable child charts before resolution" >&2
  exit 1
}

grep -Fq 'publish-selected-child-charts.sh' "$artifact_workflow" || {
  echo "artifact workflow must use the canonical child-chart publisher" >&2
  exit 1
}

grep -Fq -- '--selected-child-charts' "$artifact_workflow" || {
  echo "artifact workflow must pass the selected child-chart manifest to the resolver" >&2
  exit 1
}

if grep -Fq -- '-main.${GITHUB_RUN_NUMBER}' "$artifact_workflow"; then
  echo "artifact workflow must not substitute -main prereleases for stable child dependencies" >&2
  exit 1
fi

grep -Fq "waiting for" "$resolver" || {
  echo "resolver must wait for a pinned artifact still being published" >&2
  exit 1
}

grep -Fq 'run Publish selected stable child charts first' "$resolver" || {
  echo "resolver must provide an actionable missing child-chart diagnostic" >&2
  exit 1
}

grep -Fq 'published child chart digest does not match selected immutable artifact' "$resolver" || {
  echo "resolver must verify selected child-chart digests" >&2
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

grep -Fq -- '--artifact-report "$REPORT"' "$workflow" || {
  echo "release compatibility manifest must retain confirmed child-chart digests" >&2
  exit 1
}

grep -Fq 'latest_published_umbrella' "$resolver" || {
  echo "resolver must verify the predecessor umbrella exists in OCI" >&2
  exit 1
}

if grep -Fq 'latest_image_tag' "$resolver" || grep -Fq 'package_versions' "$resolver"; then
  echo "resolver must not scan GHCR and select an unrelated latest image" >&2
  exit 1
fi

for required in \
  "ghcr.io/envpilot/api" \
  "ghcr.io/envpilot/frontend" \
  "ghcr.io/envpilot/agent" \
  "ghcr.io/envpilot/runner" \
  "ghcr.io/envpilot/platform-reconciler"; do
  grep -Fq "$required" "$root/deploy/helm/envpilot/values.yaml" || { echo "pinned values missing: $required" >&2; exit 1; }
done

if grep -Eq ':[[:space:]]*(latest|main)([[:space:]"'"'"'@]|$)|tag:[[:space:]]*(latest|main)([[:space:]"'"'"'@]|$)' "$workflow"; then
  echo "automatic umbrella releases must not use mutable latest/main refs" >&2
  exit 1
fi

echo "release-on-main workflow contract is valid"
