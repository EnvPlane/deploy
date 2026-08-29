#!/usr/bin/env bash
set -euo pipefail

# Proves that the complete published compatibility set can be consumed from a
# clean machine. Credentials from the release job are deliberately discarded.
manifest=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest="${2:-}"; shift 2 ;;
    *) echo "usage: $0 --manifest <compatibility-release.json>" >&2; exit 2 ;;
  esac
done
[[ -f "$manifest" ]] || { echo "--manifest is required" >&2; exit 2; }

jq -e '
  .schemaVersion == 1 and
  (.umbrella.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.images | length == 6) and (.childCharts | length == 6) and
  all(.images[]; (.repository | test("^ghcr\\.io/envplane/[a-z0-9._-]+$")) and
    (.digest | test("^sha256:[0-9a-f]{64}$")) and
    .attestations.sbom.required == true and .attestations.provenance.required == true) and
  all(.childCharts[]; (.repository | test("^oci://ghcr\\.io/envplane/[a-z0-9._-]+$")) and
    (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.digest | test("^sha256:[0-9a-f]{64}$")) and
    .attestations.sbom.required == true and .attestations.provenance.required == true)
' "$manifest" >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export DOCKER_CONFIG="$tmp/docker"
export HELM_REGISTRY_CONFIG="$tmp/helm/registry.json"
export HELM_REPOSITORY_CONFIG="$tmp/helm/repositories.yaml"
mkdir -p "$DOCKER_CONFIG" "$(dirname "$HELM_REGISTRY_CONFIG")"
printf '{"auths":{}}\n' >"$DOCKER_CONFIG/config.json"
printf '{"auths":{}}\n' >"$HELM_REGISTRY_CONFIG"
: >"$HELM_REPOSITORY_CONFIG"

version="$(jq -er '.umbrella.version' "$manifest")"
helm pull oci://ghcr.io/envplane/envplane --version "$version" --destination "$tmp"

while IFS=$'\t' read -r repository chart_version; do
  helm pull "$repository" --version "$chart_version" --destination "$tmp"
done < <(jq -r '.childCharts[] | [.repository, .version] | @tsv' "$manifest")

while IFS=$'\t' read -r repository digest; do
  for platform in linux/amd64 linux/arm64; do
    docker pull --platform "$platform" "$repository@$digest" >/dev/null
  done
done < <(jq -r '.images[] | [.repository, .digest] | @tsv' "$manifest")

echo "anonymous OCI pull contract passed for umbrella, child charts, amd64 and arm64 images"
