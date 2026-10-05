#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output="$(bash "$root/scripts/render-remote-project-binding-access.sh" --cluster-id bethunder-local --project-id app)"
grep -Fq 'ep-agent-c05a23617cac-envplane-agent-capability-637e570683' <<<"$output"
if grep -Eq 'verbs:.*(create|bind|escalate|\*)' <<<"$output"; then echo "unexpected privilege" >&2; exit 1; fi
printf '%s' "$output" | ruby -ryaml -e 'docs=YAML.load_stream(STDIN.read); rules=docs[0].fetch("rules"); abort unless rules.size==1 && rules[0].fetch("resourceNames").size==3 && docs[1].fetch("subjects").size==1'
other="$(bash "$root/scripts/render-remote-project-binding-access.sh" --cluster-id customer-west --project-id arbitrary-orders --runtime-namespace runtime)"
if grep -Fq 'ep-agent-c05a23617cac' <<<"$other"; then exit 1; fi
if bash "$root/scripts/render-remote-project-binding-access.sh" --cluster-id west --project-id '../foreign' >/dev/null 2>&1; then exit 1; fi
echo "remote project exact binding access contract passed"
