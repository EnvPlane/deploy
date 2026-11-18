#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -f "$tmp/kubectl" "$tmp/operations"; rmdir "$tmp"' EXIT
export PREVIEW_PROBE_OPERATIONS="$tmp/operations"
export PATH="$tmp:$PATH"
cat >"$tmp/kubectl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PREVIEW_PROBE_OPERATIONS"
role=envplane-control-plane-preview-networkpolicy-writer
if [[ "$1 $2" == '-n default' ]]; then
  if [[ "${PREVIEW_PROBE_HA:-false}" == true ]]; then
    echo '{"items":[{"endpoints":[{"addresses":["192.0.2.1","192.0.2.2"]}]}]}'
  else
    echo '{"items":[{"endpoints":[{"addresses":["192.0.2.1"]}]}]}'
  fi
elif [[ "$1 $2" == 'get validatingadmissionpolicybinding' ]]; then
  printf '{"metadata":{"uid":"fixture-uid"},"spec":{"policyName":"%s","validationActions":["Deny"]}}\n' "$role"
elif [[ "$1 $2" == 'create namespace' || "$1 $2" == 'delete namespace' ]]; then
  exit 0
elif [[ "$1 $2" == 'create clusterrolebinding' || "$*" == *':not-a-managed-runner'* || "$*" == *' -n envplane-executors '* ]]; then
  if [[ "${PREVIEW_PROBE_BAD:-false}" == true ]]; then
    echo 'Forbidden: caller is not authorized' >&2
  else
    echo "ValidatingAdmissionPolicy '$role' with binding '$role' denied request: Preview NetworkPolicy writer may only be delegated" >&2
  fi
  exit 1
elif [[ "$1 $2" != 'create rolebinding' || "$*" != *'--dry-run=server'* ]]; then
  exit 2
fi
SH
chmod +x "$tmp/kubectl"
run() { bash "$root/scripts/verify-preview-admission.sh" envplane-control-plane envplane-executors; }
[[ "$(run)" == fixture-uid ]]
grep -q '^delete namespace envplane-pr-admission-' "$PREVIEW_PROBE_OPERATIONS"
: >"$PREVIEW_PROBE_OPERATIONS"
if result="$(PREVIEW_PROBE_HA=true run)" || [[ -n "$result" ]] || grep -q '^create namespace' "$PREVIEW_PROBE_OPERATIONS"; then
  echo 'A single sampled endpoint must not enable a multi-server target' >&2
  exit 1
fi
: >"$PREVIEW_PROBE_OPERATIONS"
if result="$(PREVIEW_PROBE_BAD=true run)" || [[ -n "$result" ]]; then
  echo 'A generic RBAC error must not enable delegation' >&2
  exit 1
fi
grep -q '^delete namespace envplane-pr-admission-' "$PREVIEW_PROBE_OPERATIONS"
