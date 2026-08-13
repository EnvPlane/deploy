#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root_dir/scripts/sync-namespaced-registry-secret.sh"

bash -n "$script"
help="$($script --help)"
grep -Fq -- '--source-namespace' <<<"$help"
grep -Fq -- '--target-namespace' <<<"$help"
grep -Fq -- '--secret' <<<"$help"

# The script may stream the Secret directly between kubectl processes, but it
# must neither serialize it as YAML for terminal output nor force-overwrite a
# credential owned by another controller.
! grep -Fq -- '-o yaml' "$script"
! grep -Fq -- '--force-conflicts' "$script"
grep -Fq -- 'get secret "$secret_name" -o json' "$script"
grep -Fq -- 'apply --server-side --field-manager=envpilot-registry-secret-sync -f - >/dev/null' "$script"

echo "namespaced registry Secret sync script contract passed"
