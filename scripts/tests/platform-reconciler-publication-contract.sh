#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
publisher="$root/.github/workflows/publish-platform-reconciler.yaml"
pin_workflow="$root/.github/workflows/propose-runtime-image-update.yaml"

grep -Fq 'docker/build-push-action@v7' "$publisher" || {
  echo "platform reconciler must be built and pushed by CI" >&2
  exit 1
}
grep -Fq 'gh api "repos/${GITHUB_REPOSITORY}/dispatches"' "$publisher" || {
  echo "platform reconciler publication must dispatch the image pin workflow" >&2
  exit 1
}
grep -Fq 'platform-reconciler' "$pin_workflow" || {
  echo "runtime image pin workflow must support platform-reconciler" >&2
  exit 1
}
grep -Fq 'ghcr.io/envplane/platform-reconciler' "$pin_workflow" || {
  echo "runtime image pin workflow must allow the canonical reconciler image" >&2
  exit 1
}

echo "platform reconciler publication contract is valid"
