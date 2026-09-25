#!/usr/bin/env bash
# Release-level smoke check: the immutable control-plane image must contain the
# AI provider routes and Anthropic adapter claimed by its compatibility record.
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

if [[ "$image" =~ ^(ghcr\.io/envplane/api):sha-[0-9a-f]{40}$ ]]; then
  [[ "$expected_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "tagged control-plane image requires an expected immutable digest" >&2
    exit 2
  }
  repository="${image%%:*}"
  actual_digest="$(docker buildx imagetools inspect "$image" 2>/dev/null | awk '/^Digest:[[:space:]]+sha256:[0-9a-f]{64}$/ {print $2; exit}' || true)"
  [[ "$actual_digest" == "$expected_digest" ]] || {
    echo "control-plane image tag does not resolve to the expected immutable digest" >&2
    exit 1
  }
  image="$repository@$expected_digest"
elif [[ "$image" =~ ^ghcr\.io/envplane/api@sha256:[0-9a-f]{64}$ ]]; then
  expected_digest="${image##*@}"
else
  echo "image must be the immutable EnvPlane control-plane digest" >&2
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
docker cp "$container:/usr/local/bin/envplane" "$tmp/envplane"

for marker in '/api/v1/tenants/{tenantID}/ai-provider-credentials' 'https://api.anthropic.com/v1/messages'; do
  if ! grep -a -F -q -- "$marker" "$tmp/envplane"; then
    echo "control-plane image is missing required AI provider runtime marker: $marker" >&2
    exit 1
  fi
done

echo "control-plane AI provider routes are present in $image"
