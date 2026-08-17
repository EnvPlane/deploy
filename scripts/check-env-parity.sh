#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
strict="${PARITY_STRICT:-1}"
failures=0

check_chart() {
  local service="$1" chart="$2" source_dir="$3"
  local rendered source name
  if [[ ! -d "$repo_root/../$source_dir" ]]; then
    echo "[$service] source checkout not present; parity check deferred to the owning repository"
    return
  fi
  rendered="$(mktemp)"
  trap 'rm -f "$rendered"' RETURN
  helm template parity "$repo_root/deploy/helm/$chart" \
    --set postgres.auth.existingSecret=parity-postgres \
    --set postgres.tls.enabled=false >"$rendered"
  if command -v rg >/dev/null 2>&1; then
    source="$(rg -o 'ENVPILOT_[A-Z0-9_]+' "$repo_root/../$source_dir" --glob '*.go' --glob '*.ts' --glob '*.tsx' --glob '!**/*_test.go' --glob '!**/*.test.ts' --glob '!**/*.test.tsx' | sed 's/.*://' | sort -u || true)"
    rendered_vars="$(rg -o 'name:[[:space:]]+ENVPILOT_[A-Z0-9_]+' "$rendered" | sed -E 's/.*name:[[:space:]]+//' | sort -u || true)"
  else
    source="$(find "$repo_root/../$source_dir" -type f \( -name '*.go' -o -name '*.ts' -o -name '*.tsx' \) ! -name '*_test.go' ! -name '*.test.ts' ! -name '*.test.tsx' -print0 | xargs -0 grep -Eho 'ENVPILOT_[A-Z0-9_]+' | sort -u || true)"
    rendered_vars="$(grep -Eho 'name:[[:space:]]+ENVPILOT_[A-Z0-9_]+' "$rendered" | sed -E 's/.*name:[[:space:]]+//' | sort -u || true)"
  fi
  echo "[$service]"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    case "$name" in
      ENVPILOT_POSTGRES_PASSWORD) continue ;;
    esac
    if ! grep -Fxq "$name" <<< "$source"; then
      echo "  rendered but not declared by production code: $name"
      failures=$((failures + 1))
    fi
  done <<< "$rendered_vars"
}

check_chart runner envpilot-runner runner
check_chart webhook envpilot-webhook webhook
check_chart control-plane envpilot-control-plane control-plane
check_chart agent envpilot-agent agent

if [[ "$strict" == "1" && "$failures" -gt 0 ]]; then
  echo "environment parity failed: $failures missing rendered variables" >&2
  exit 1
fi
echo "environment parity report complete ($failures rendered variables are not declared by production code)"
