#!/usr/bin/env bash
# Reject a compatibility report that was built from an older deploy/main.
set -euo pipefail

report=""
main_revision=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) report="${2:-}"; shift 2 ;;
    --main-revision) main_revision="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -s "$report" ]] || { echo "compatibility report is missing" >&2; exit 2; }
[[ "$main_revision" =~ ^[0-9a-f]{40}$ ]] || { echo "main revision must be a full lowercase commit SHA" >&2; exit 2; }
source_revision="$(jq -er '.sourceRevision' "$report")"
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { echo "compatibility report has an invalid source revision" >&2; exit 2; }

if [[ "$source_revision" != "$main_revision" ]]; then
  echo "compatibility report is stale: it was built from $source_revision, but deploy/main is $main_revision" >&2
  echo "wait for Publish deploy image and charts (main) for the current main revision, then release that artifact" >&2
  exit 1
fi

echo "compatibility report matches deploy/main"
