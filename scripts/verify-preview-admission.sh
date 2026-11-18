#!/usr/bin/env bash
# Print only the verified binding UID. Intended for the privileged installer,
# never for the control-plane or a managed Runner.
set -euo pipefail
[[ $# -ge 2 ]] || { echo 'Usage: verify-preview-admission.sh CONTROL_PLANE_FULLNAME EXECUTOR_NAMESPACE [kubectl connection flags]' >&2; exit 2; }
policy="$1-preview-networkpolicy-writer"
executors="$2"
shift 2
k() { kubectl "$@"; }
connection=("$@")
assert_single_apiserver() {
  k "${connection[@]}" -n default get endpointslices -l kubernetes.io/service-name=kubernetes -o json |
    jq -e '[.items[].endpoints[].addresses[]] | unique | length == 1' >/dev/null ||
    { echo 'Cannot prove admission through every API server; delegation remains disabled' >&2; return 1; }
}
assert_single_apiserver
read_binding() {
  k "${connection[@]}" get validatingadmissionpolicybinding "$policy" -o json |
    jq -er --arg policy "$policy" 'select(.spec.policyName == $policy and (.spec.validationActions | index("Deny")) != null) | .metadata.uid'
}
uid="$(read_binding)"
# Match only the denial from this exact policy and binding, not a generic 403
# such as missing operator privileges or a different admission policy.
denial="ValidatingAdmissionPolicy '$policy' with binding '$policy' denied request: Preview NetworkPolicy writer may only be delegated"
subject="$executors:ep-runner-admission-probe-envplane-runner"
probe="envplane-pr-admission-$(openssl rand -hex 8)"
k "${connection[@]}" create namespace "$probe" >&2
cleanup() { k "${connection[@]}" delete namespace "$probe" --wait=false >&2; }
trap cleanup EXIT
assert_denied() {
  local evidence
  if evidence="$(k "${connection[@]}" create "$@" --clusterrole="$policy" --dry-run=server 2>&1)"; then
    return 1
  fi
  if [[ "$evidence" != *"$denial"* ]]; then
    printf '%s\n' "$evidence" >&2
    return 2
  fi
}
verified=false
for _ in {1..30}; do
  if assert_denied clusterrolebinding "$probe" --serviceaccount="$subject"; then
    verified=true
    break
  else
    result=$?
    [[ "$result" == 1 ]] || exit "$result"
  fi
  sleep 1
done
[[ "$verified" == true ]] || { echo 'Preview admission did not enforce the expected cluster-wide denial' >&2; exit 1; }
assert_denied rolebinding "$probe" -n "$probe" --serviceaccount="$executors:not-a-managed-runner"
assert_denied rolebinding "$probe" -n "$executors" --serviceaccount="$subject"
k "${connection[@]}" create rolebinding "$probe" -n "$probe" --clusterrole="$policy" --serviceaccount="$subject" --dry-run=server >&2
[[ "$(read_binding)" == "$uid" ]] || { echo 'Preview admission binding changed during verification' >&2; exit 1; }
assert_single_apiserver
cleanup
trap - EXIT
printf '%s\n' "$uid"
