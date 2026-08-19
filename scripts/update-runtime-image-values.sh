#!/usr/bin/env bash
# Updates exactly one runtime image in the umbrella values file. This script is
# intentionally strict because repository_dispatch payloads cross repository
# boundaries and must not turn into arbitrary values-file edits.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update-runtime-image-values.sh \
  --component <control-plane|frontend|agent|runner|webhook|platform-reconciler> \
  --repository <ghcr.io/EnvPlane/...> \
  --tag <sha-40-hex> \
  --digest <sha256:64-hex> \
  --source-revision <40-hex> \
  [--release <identifier>] [--values-file <path>] \
  [--release-file <path>] [--report-file <path>]
EOF
}

die() {
  echo "error: $*" >&2
  exit 2
}

component=""
repository=""
tag=""
digest=""
source_revision=""
release=""
values_file="deploy/helm/envpilot/values.yaml"
release_file=""
report_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --component) component="${2:-}"; shift 2 ;;
    --repository) repository="${2:-}"; shift 2 ;;
    --tag) tag="${2:-}"; shift 2 ;;
    --digest) digest="${2:-}"; shift 2 ;;
    --source-revision) source_revision="${2:-}"; shift 2 ;;
    --release) release="${2:-}"; shift 2 ;;
    --values-file) values_file="${2:-}"; shift 2 ;;
    --release-file) release_file="${2:-}"; shift 2 ;;
    --report-file) report_file="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$component" in
  control-plane) section="envpilot-control-plane"; expected_repository="ghcr.io/envplane/api" ;;
  frontend) section="envpilot-frontend"; expected_repository="ghcr.io/envplane/frontend" ;;
  agent) section="envpilot-agent"; expected_repository="ghcr.io/envplane/agent" ;;
  runner) section="envpilot-runner"; expected_repository="ghcr.io/envplane/runner" ;;
  webhook) section="envpilot-webhook"; expected_repository="ghcr.io/envplane/webhook" ;;
  platform-reconciler) section="platformDependencyReconciler"; expected_repository="ghcr.io/envplane/platform-reconciler" ;;
  *) die "unsupported component: $component" ;;
esac

[[ "$repository" == "$expected_repository" ]] || die "repository for $component must be $expected_repository"
[[ "$tag" =~ ^sha-[0-9a-f]{40}$ ]] || die "tag must be sha- followed by a full lowercase commit SHA"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "digest must be a lowercase sha256 digest"
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || die "source revision must be a full lowercase commit SHA"
[[ -n "$release" ]] || release="$tag"
[[ -f "$values_file" ]] || die "values file not found: $values_file"

case "$component" in
  control-plane) release_key="api" ;;
  frontend) release_key="frontend" ;;
  agent) release_key="agent" ;;
  runner) release_key="runner" ;;
  webhook) release_key="webhook" ;;
  platform-reconciler) release_key="platformReconciler" ;;
esac

old_repository="$(awk -v section="$section" '
  $0 == section ":" { in_section=1 }
  in_section && $0 != section ":" && $0 ~ /^[^[:space:]]/ { exit }
  in_section && $0 ~ /^    repository:/ { sub(/^    repository:[[:space:]]*/, ""); print; exit }
' "$values_file")"
old_tag="$(awk -v section="$section" '
  $0 == section ":" { in_section=1 }
  in_section && $0 != section ":" && $0 ~ /^[^[:space:]]/ { exit }
  in_section && $0 ~ /^    tag:/ { sub(/^    tag:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
' "$values_file")"
old_digest="$(awk -v section="$section" '
  $0 == section ":" { in_section=1 }
  in_section && $0 != section ":" && $0 ~ /^[^[:space:]]/ { exit }
  in_section && $0 ~ /^    digest:/ { sub(/^    digest:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
' "$values_file")"
old_reference="${old_repository}:${old_tag}"
[[ -n "$old_repository" && -n "$old_tag" ]] || die "could not read current image reference for $component"

tmp_file="$(mktemp "${values_file}.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

if ! awk \
  -v section="$section" \
  -v repository="$repository" \
  -v tag="$tag" \
  -v digest="$digest" \
  -v source_revision="$source_revision" \
  -v release="$release" '
  $0 == section ":" { in_section = 1; section_found = 1 }
  in_section && $0 != section ":" && $0 ~ /^[^[:space:]]/ { in_section = 0; in_image = 0 }
  in_section && $0 == "  image:" { in_image = 1; image_found = 1 }
  in_image && $0 ~ /^  [A-Za-z0-9][A-Za-z0-9_-]*:/ && $0 != "  image:" { in_image = 0 }
  in_image && $0 ~ /^    repository:/ { print "    repository: " repository; repository_found = 1; next }
  in_image && $0 ~ /^    tag:/ { print "    tag: \"" tag "\""; tag_found = 1; next }
  in_image && $0 ~ /^    digest:/ { print "    digest: \"" digest "\""; digest_found = 1; next }
  in_image && $0 ~ /^    sourceRevision:/ { print "    sourceRevision: \"" source_revision "\""; source_found = 1; next }
  in_image && $0 ~ /^    release:/ { print "    release: \"" release "\""; release_found = 1; next }
  { print }
  END {
    if (!section_found || !image_found || !repository_found || !tag_found || !digest_found || !source_found || !release_found) {
      exit 3
    }
  }
' "$values_file" > "$tmp_file"; then
  die "failed to update the expected image block for $component"
fi

mv "$tmp_file" "$values_file"
trap - EXIT

if [[ -n "$release_file" ]]; then
  [[ -f "$release_file" ]] || die "release manifest not found: $release_file"
  release_tmp="$(mktemp "${release_file}.XXXXXX")"
  trap 'rm -f "$release_tmp"' EXIT
  if ! awk \
    -v image_key="$release_key" \
    -v repository="$repository" \
    -v tag="$tag" \
    -v digest="$digest" \
    -v source_revision="$source_revision" '
    $0 == "images:" { in_images=1 }
    in_images && $0 != "images:" && $0 ~ /^[^[:space:]]/ { in_images=0 }
    in_images && index($0, "  " image_key ":") == 1 { print "  " image_key ": " repository ":" tag; next }
    $0 == "imagePins:" { in_pins=1 }
    in_pins && $0 != "imagePins:" && $0 ~ /^[^[:space:]]/ { in_pins=0; in_pin=0 }
    in_pins && $0 == "  " image_key ":" { in_pin=1; pin_found=1 }
    in_pin && $0 ~ /^  [a-z][a-z-]*:/ && $0 != "  " image_key ":" { in_pin=0 }
    in_pin && $0 ~ /^    repository:/ { print "    repository: " repository; repository_found=1; next }
    in_pin && $0 ~ /^    tag:/ { print "    tag: \"" tag "\""; tag_found=1; next }
    in_pin && $0 ~ /^    digest:/ { print "    digest: \"" digest "\""; digest_found=1; next }
    in_pin && $0 ~ /^    sourceRevision:/ { print "    sourceRevision: \"" source_revision "\""; source_found=1; next }
    { print }
    END {
      if (!pin_found || !repository_found || !tag_found || !digest_found || !source_found) exit 3
    }
  ' "$release_file" > "$release_tmp"; then
    die "failed to update compatibility metadata for $component"
  fi
  mv "$release_tmp" "$release_file"
  trap - EXIT
fi

if [[ -n "$report_file" ]]; then
  mkdir -p "$(dirname "$report_file")"
  jq -cn \
    --arg oldReference "$old_reference" \
    --arg oldDigest "$old_digest" \
    --arg newReference "$repository:$tag@$digest" \
    --arg component "$component" \
    '{component:$component,oldReference:$oldReference,oldDigest:$oldDigest,newReference:$newReference}' \
    > "$report_file"
fi
echo "updated $component image to $repository@$digest ($tag)"
