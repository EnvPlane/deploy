#!/usr/bin/env bash
# Reject mutable GitHub Actions refs in every workflow file.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
found=0
while IFS= read -r line; do
  found=1
  ref="${line##*@}"
  ref="${ref%%[[:space:]#]*}"
  if [[ ! "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "GitHub Action is not pinned to a full commit SHA: $line" >&2
    exit 1
  fi
done < <(grep -RInE --include='*.yml' --include='*.yaml' '^[[:space:]-]*uses:[[:space:]]*[^#[:space:]]+@[^#[:space:]]+' "$root/.github/workflows" || true)

if [[ "$found" -eq 0 ]]; then
  echo "no GitHub Actions found in workflow files" >&2
  exit 1
fi
echo "all GitHub Actions are pinned to full commit SHAs"
