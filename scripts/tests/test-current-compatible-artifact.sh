#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

current="0123456789abcdef0123456789abcdef01234567"
stale="89abcdef0123456789abcdef0123456789abcdef"
jq -n --arg revision "$current" '{schemaVersion:1,sourceRevision:$revision}' > "$tmp/current.json"
jq -n --arg revision "$stale" '{schemaVersion:1,sourceRevision:$revision}' > "$tmp/stale.json"

"$root/scripts/ensure-current-compatible-artifact.sh" --report "$tmp/current.json" --main-revision "$current" >/dev/null
if "$root/scripts/ensure-current-compatible-artifact.sh" --report "$tmp/stale.json" --main-revision "$current" >/dev/null 2>&1; then
  echo "stale compatibility report was accepted" >&2
  exit 1
fi
echo "current compatibility artifact selection test passed"
