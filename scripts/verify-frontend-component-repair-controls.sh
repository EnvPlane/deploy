#!/usr/bin/env bash
# Release-level smoke check: the image pinned into the umbrella must contain
# the Draft-bootstrap component repair controls, not merely a matching chart.
set -euo pipefail

image=""
expected_digest=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) image="${2:-}"; shift 2 ;;
    --digest) expected_digest="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "$image" =~ ^(ghcr\.io/envplane/frontend):sha-[0-9a-f]{40}$ ]]; then
  [[ "$expected_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "tagged frontend image requires an expected immutable digest" >&2
    exit 2
  }
  docker buildx imagetools inspect "$image" | grep -Fq "$expected_digest" || {
    echo "frontend image tag does not resolve to the expected immutable digest" >&2
    exit 1
  }
elif [[ "$image" =~ ^ghcr\.io/envplane/frontend@sha256:[0-9a-f]{64}$ ]]; then
  expected_digest="${image##*@}"
else
  echo "image must be the immutable EnvPlane frontend digest" >&2
  exit 2
fi

tmp="$(mktemp -d)"
container=""
cleanup() {
  [[ -n "$container" ]] && docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

docker pull "$image" >/dev/null
container="$(docker create "$image")"
docker cp "$container:/app/.next" "$tmp/.next"

for marker in 'Configured application components' 'Save component changes' 'Component ID' 'Default branch'; do
  if ! grep -R -a -F -q -- "$marker" "$tmp/.next"; then
    echo "frontend image is missing required component-repair control: $marker" >&2
    exit 1
  fi
done

echo "frontend component-repair controls are present in $image"
