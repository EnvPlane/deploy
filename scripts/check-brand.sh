#!/usr/bin/env bash
set -euo pipefail

target="${1:-}"
if [[ -z "$target" ]]; then
  target="$(git rev-parse --show-toplevel)"
fi

if [[ ! -e "$target" ]]; then
  echo "brand check target does not exist: $target" >&2
  exit 2
fi

deprecated_brand="$(printf '%s%s' 'Env' 'Pilot')"

if command -v rg >/dev/null 2>&1; then
  search=(rg -n --hidden -g '!**/.git/**' -g '!node_modules/**' -g '!**/.next/**' -g '!vendor/**' -g '!dist/**' -g '!build/**' -e "$deprecated_brand" "$target")
else
  search=(grep -RInI --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=vendor --exclude-dir=dist --exclude-dir=build -- "$deprecated_brand" "$target")
fi

if "${search[@]}"; then
  echo "Use the EnvPlane product name and the ENVPLANE_*/envplane.io/* identifiers consistently." >&2
  exit 1
fi
