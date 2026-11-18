#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -f "$tmp/kubectl" "$tmp/sleep" "$tmp/operations"; rmdir "$tmp"' EXIT
export PREVIEW_PROBE_OPERATIONS="$tmp/operations"
export PATH="$tmp:$PATH"
cat >"$tmp/kubectl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PREVIEW_PROBE_OPERATIONS"
cat >/dev/null
role=envplane-control-plane-preview-networkpolicy-writer
[[ "$1" == --request-timeout=10s ]]; shift
endpoint=client
if [[ "$1" == --server ]]; then endpoint="$2"; shift 2; fi
if [[ "$endpoint" == https://192.0.2.2:6443 && "${PREVIEW_SCENARIO:-}" == unavailable ]]; then
  echo 'connection refused' >&2
  exit 1
fi
if [[ "$1 $2" == '-n default' ]]; then
  addresses='["192.0.2.1"]'
  ready=true
  [[ "${PREVIEW_PROBE_HA:-false}" != true ]] || addresses='["192.0.2.1","192.0.2.2"]'
  [[ "${PREVIEW_SCENARIO:-}" != unready ]] || ready=false
  if [[ "$endpoint" == https://192.0.2.2:6443 && "${PREVIEW_SCENARIO:-}" == drift ]]; then
    addresses='["192.0.2.1","192.0.2.3"]'
  fi
  printf '{"items":[{"addressType":"IPv4","ports":[{"name":"https","protocol":"TCP","port":6443}],"endpoints":[{"addresses":%s,"conditions":{"ready":%s}}]}]}\n' "$addresses" "$ready"
elif [[ "$1 $2" == 'config view' ]]; then
  echo '{"clusters":[{"cluster":{"server":"https://balance.example"}}]}'
elif [[ "$1 $2" == 'get namespace' ]]; then
  echo '{"metadata":{"uid":"1234"}}'
elif [[ "$1 $2" == 'get validatingadmissionpolicy' ]]; then
  generation=1
  [[ "$endpoint:${PREVIEW_SCENARIO:-}" != https://192.0.2.2:6443:changed-policy ]] || generation=2
  printf '{"metadata":{"uid":"cafe","generation":%s},"spec":{"failurePolicy":"Fail"}}\n' "$generation"
elif [[ "$1 $2" == 'get validatingadmissionpolicybinding' ]]; then
  printf '{"metadata":{"uid":"abcd","generation":1},"spec":{"policyName":"%s","validationActions":["Deny"]}}\n' "$role"
elif [[ "$1 $2" == 'create namespace' || "$1 $2" == 'delete namespace' ]]; then
  exit 0
elif [[ "$1 $2" == 'create clusterrolebinding' || "$*" == *':not-a-managed-runner'* || "$*" == *' -n envplane-executors '* ]]; then
  if [[ "$1 $2" == 'create clusterrolebinding' && "$endpoint:${PREVIEW_SCENARIO:-}" == https://192.0.2.2:6443:allows ]]; then
    exit 0
  fi
  if [[ "${PREVIEW_PROBE_BAD:-false}" == true || "$endpoint:${PREVIEW_SCENARIO:-}" == https://192.0.2.2:6443:wrong-denial ]]; then
    echo 'Forbidden: caller is not authorized' >&2
  else
    echo "ValidatingAdmissionPolicy '$role' with binding '$role' denied request: Preview NetworkPolicy writer may only be delegated" >&2
  fi
  exit 1
elif [[ "$1 $2" != 'create rolebinding' || "$*" != *'--dry-run=server'* ]]; then
  exit 2
fi
SH
ln -s /usr/bin/true "$tmp/sleep"
chmod +x "$tmp/kubectl"
run() { bash "$root/scripts/verify-preview-admission.sh" envplane-control-plane envplane-executors "$@"; }
[[ "$(run)" == abcd:1:cafe:1:1234 ]]
grep -q 'delete namespace envplane-pr-admission-' "$PREVIEW_PROBE_OPERATIONS"
: >"$PREVIEW_PROBE_OPERATIONS"
if result="$(PREVIEW_PROBE_HA=true run)" || [[ -n "$result" ]] || grep -q 'create namespace' "$PREVIEW_PROBE_OPERATIONS"; then
  echo 'A single sampled endpoint must not enable a multi-server target' >&2
  exit 1
fi
: >"$PREVIEW_PROBE_OPERATIONS"
if result="$(PREVIEW_PROBE_BAD=true run)" || [[ -n "$result" ]]; then
  echo 'A generic RBAC error must not enable delegation' >&2
  exit 1
fi
grep -q 'delete namespace envplane-pr-admission-' "$PREVIEW_PROBE_OPERATIONS"
: >"$PREVIEW_PROBE_OPERATIONS"
[[ "$(PREVIEW_PROBE_HA=true run --expected-api-servers 2)" == abcd:1:cafe:1:1234 ]]
for endpoint in https://192.0.2.1:6443 https://192.0.2.2:6443; do
  [[ "$(grep -Fc -- "--server $endpoint create " "$PREVIEW_PROBE_OPERATIONS")" == 4 ]]
done
for scenario in unavailable drift changed-policy wrong-denial allows unready; do
  if result="$(PREVIEW_PROBE_HA=true PREVIEW_SCENARIO="$scenario" run --expected-api-servers 2)" || [[ -n "$result" ]]; then
    echo "HA verifier must fail closed: $scenario" >&2
    exit 1
  fi
done
