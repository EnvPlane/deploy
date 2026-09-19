#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/envplane-chart-version-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

git init -q "$tmp"
git -C "$tmp" config user.email test@example.invalid
git -C "$tmp" config user.name chart-version-test
mkdir -p "$tmp/deploy/helm/envplane-control-plane/templates"
printf 'apiVersion: v2\nname: envplane-control-plane\nversion: 0.3.22\n' >"$tmp/deploy/helm/envplane-control-plane/Chart.yaml"
printf 'first\n' >"$tmp/deploy/helm/envplane-control-plane/templates/config.yaml"
git -C "$tmp" add .
git -C "$tmp" commit -qm baseline

printf 'changed\n' >"$tmp/deploy/helm/envplane-control-plane/templates/config.yaml"
git -C "$tmp" add .
git -C "$tmp" commit -qm changed-without-version-bump
if (cd "$tmp" && "$root/scripts/verify-changed-child-chart-versions.sh" --base HEAD~1 --head HEAD) 2>/dev/null; then
  echo 'expected changed child chart without a version bump to fail' >&2
  exit 1
fi

sed -i.bak 's/version: 0.3.22/version: 0.3.23/' "$tmp/deploy/helm/envplane-control-plane/Chart.yaml"
rm -f "$tmp/deploy/helm/envplane-control-plane/Chart.yaml.bak"
git -C "$tmp" add .
git -C "$tmp" commit -qm version-bump
(cd "$tmp" && "$root/scripts/verify-changed-child-chart-versions.sh" --base HEAD~1 --head HEAD)
