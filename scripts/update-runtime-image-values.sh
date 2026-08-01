#!/usr/bin/env bash
# Updates exactly one runtime image in the umbrella values file. This script is
# intentionally strict because repository_dispatch payloads cross repository
# boundaries and must not turn into arbitrary values-file edits.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update-runtime-image-values.sh \
  --component <control-plane|frontend|agent|runner> \
  --repository <ghcr.io/envpilot/...> \
  --tag <sha-40-hex> \
  --digest <sha256:64-hex> \
  --source-revision <40-hex> \
  [--release <identifier>] [--values-file <path>]
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --component) component="${2:-}"; shift 2 ;;
    --repository) repository="${2:-}"; shift 2 ;;
    --tag) tag="${2:-}"; shift 2 ;;
    --digest) digest="${2:-}"; shift 2 ;;
    --source-revision) source_revision="${2:-}"; shift 2 ;;
    --release) release="${2:-}"; shift 2 ;;
    --values-file) values_file="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$component" in
  control-plane) section="envpilot-control-plane"; expected_repository="ghcr.io/envpilot/api" ;;
  frontend) section="envpilot-frontend"; expected_repository="ghcr.io/envpilot/frontend" ;;
  agent) section="envpilot-agent"; expected_repository="ghcr.io/envpilot/agent" ;;
  runner) section="envpilot-runner"; expected_repository="ghcr.io/envpilot/runner" ;;
  *) die "unsupported component: $component" ;;
esac

[[ "$repository" == "$expected_repository" ]] || die "repository for $component must be $expected_repository"
[[ "$tag" =~ ^sha-[0-9a-f]{40}$ ]] || die "tag must be sha- followed by a full lowercase commit SHA"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "digest must be a lowercase sha256 digest"
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || die "source revision must be a full lowercase commit SHA"
[[ -n "$release" ]] || release="$tag"
[[ -f "$values_file" ]] || die "values file not found: $values_file"

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
echo "updated $component image to $repository@$digest ($tag)"
