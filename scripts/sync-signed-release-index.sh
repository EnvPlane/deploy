#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="${ENVPLANE_RELEASE_REPOSITORY:-EnvPlane/deploy}"
api="${GITHUB_API_URL:-https://api.github.com}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for command in curl jq cosign; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 2; }
done

headers=(-H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28')
if [[ -n "${GITHUB_TOKEN:-}" ]]; then headers+=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi
curl --fail --silent --show-error "${headers[@]}" "$api/repos/$repo/releases/latest" > "$tmp/release.json"

version="$(jq -er '.tag_name | sub("^envplane-v"; "") | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' "$tmp/release.json")"
index_name="envplane-$version-release-index.json"
bundle_name="envplane-$version-release-index.sigstore.json"
index_url="$(jq -er --arg name "$index_name" '.assets[] | select(.name == $name) | .browser_download_url' "$tmp/release.json")"
bundle_url="$(jq -er --arg name "$bundle_name" '.assets[] | select(.name == $name) | .browser_download_url' "$tmp/release.json")"
curl --fail --silent --show-error -L "$index_url" -o "$tmp/index.json"
curl --fail --silent --show-error -L "$bundle_url" -o "$tmp/bundle.json"

cosign verify-blob \
  --bundle "$tmp/bundle.json" \
  --certificate-identity "https://github.com/EnvPlane/deploy/.github/workflows/release-on-main.yaml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "$tmp/index.json" >/dev/null

mkdir -p "$root/docs/generated"
cp "$tmp/index.json" "$root/docs/generated/stable-release-index.json"
"$root/scripts/render-install-docs-from-release-index.sh"
echo "synced signed stable release index $version"
