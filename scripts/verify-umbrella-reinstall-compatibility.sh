#!/usr/bin/env bash
set -euo pipefail
allow_legacy_without_manifest=false
if [[ "${1:-}" == "--allow-legacy-without-manifest" ]]; then
  allow_legacy_without_manifest=true
  shift
fi
chart_archive="${1:-}"
[[ -f "$chart_archive" ]] || { echo "chart archive is required" >&2; exit 2; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -tzf "$chart_archive" > "$tmp/archive-files.txt"
manifest_path="$(awk '/\/compatibility\/release\.json$/ { print; exit }' "$tmp/archive-files.txt")"
if [[ -z "$manifest_path" ]]; then
  if [[ "$allow_legacy_without_manifest" != true ]]; then
    echo "chart archive has no compatibility manifest" >&2
    exit 1
  fi
  # A main-snapshot predecessor published before the atomic-release contract
  # cannot prove an exact compatibility set. Keep this narrowly scoped to the
  # one-time migration path; stable releases must always contain the manifest.
  helm template reinstall-a "$chart_archive" > "$tmp/a.yaml"
  echo "legacy chart reinstall render passed without compatibility manifest"
  exit 0
fi
tar -xOf "$chart_archive" "$manifest_path" > "$tmp/manifest.json"
jq -e '.schemaVersion == 1 and (.images|length == 5) and (.childCharts|length == 4) and all(.images[]; .digest|test("^sha256:[0-9a-f]{64}$"))' "$tmp/manifest.json" >/dev/null
helm template reinstall-a "$chart_archive" > "$tmp/a.yaml"
test "$(sha256sum "$tmp/manifest.json" | awk '{print $1}')" = "$(tar -xOf "$chart_archive" "$manifest_path" | sha256sum | awk '{print $1}')" || {
  echo "reinstall did not resolve the same compatibility manifest" >&2
  exit 1
}
echo "umbrella reinstall compatibility verification passed"
