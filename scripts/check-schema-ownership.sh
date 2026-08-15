#!/usr/bin/env bash
set -euo pipefail

# Check the repository checkout set used by local integration tests. In a
# standalone checkout the caller must pass every repository path explicitly.
paths=()
while (($#)); do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo '--root requires a path' >&2; exit 2; }
      root="$2"
      while IFS= read -r -d '' repo; do paths+=("$repo"); done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0)
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo '--repo requires a path' >&2; exit 2; }
      paths+=("$2")
      shift 2
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ((${#paths[@]} == 0)); then
  echo 'usage: check-schema-ownership.sh --root <checkout-root> [--repo <repo>]...' >&2
  exit 2
fi

owners=()
for repo in "${paths[@]}"; do
  [[ -d "$repo" ]] || continue
  if [[ -d "$repo/migrations/postgres" ]]; then
    owners+=("$repo")
  fi
done

if ((${#owners[@]} != 1)); then
  printf 'expected exactly one migrations/postgres owner, found %d:\n' "${#owners[@]}" >&2
  printf '  %s\n' "${owners[@]}" >&2
  exit 1
fi
printf 'schema owner: %s\n' "${owners[0]}"
