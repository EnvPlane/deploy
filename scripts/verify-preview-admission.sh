#!/usr/bin/env bash
# Print only the verified admission identity. Intended for the privileged installer,
# never for the control-plane or a managed Runner.
set -euo pipefail
[[ $# -ge 2 ]] || { echo 'Usage: verify-preview-admission.sh CONTROL_PLANE_FULLNAME EXECUTOR_NAMESPACE [--expected-api-servers N] [--kubeconfig FILE] [--context NAME]' >&2; exit 2; }
policy="$1-preview-networkpolicy-writer"
executors="$2"
shift 2
expected=1
connection=()
while (( $# )); do
  case "$1" in
    --expected-api-servers) expected="${2:?}"; shift 2 ;;
    --context|--kubeconfig) connection+=("$1" "${2:?}"); shift 2 ;;
    *) echo "Unsupported verifier argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$expected" =~ ^[1-9][0-9]?$ ]] || { echo 'Expected API server count must be between 1 and 99' >&2; exit 2; }
# Never let kubectl, an exec credential provider, or a transport wrapper
# consume the endpoint loop's stdin.
base() { kubectl ${connection[@]+"${connection[@]}"} --request-timeout=10s "$@" </dev/null; }
route=()
k() {
  # HA probes must not be sent through an HTTP proxy or the client-facing LB.
  NO_PROXY='*' no_proxy='*' HTTPS_PROXY= https_proxy= HTTP_PROXY= http_proxy= ALL_PROXY= all_proxy= \
    base ${route[@]+"${route[@]}"} "$@"
}
base config view --minify -o json |
  jq -e '.clusters | length == 1 and (.[0].cluster | (.server | startswith("https://")) and
    (.["insecure-skip-tls-verify"] != true) and ((.["proxy-url"] // "") == ""))' >/dev/null ||
  { echo 'Admission verification requires a trusted HTTPS kubeconfig without an explicit proxy' >&2; exit 1; }

inventory() {
  k -n default get endpointslices -l kubernetes.io/service-name=kubernetes -o json |
    jq -er --argjson expected "$expected" '
      [.items[] |
        .addressType as $family |
        [.ports[] | select(.name=="https" and .protocol=="TCP" and
          (.port | type=="number" and .>=1 and .<=65535)) | .port] as $ports |
        .endpoints[] |
        if .conditions.ready != true or .conditions.terminating == true or
           .conditions.serving == false or ($ports|length)!=1
        then error("API endpoint is not serving trusted HTTPS") else . end |
        .addresses[] |
        if $family=="IPv4" and test("^[0-9]+(\\.[0-9]+){3}$") then .
        elif $family=="IPv6" and test("^[0-9A-Fa-f:]+$") and contains(":") then "["+. +"]"
        else error("API endpoint must use an IP address") end |
        "https://"+.+":"+($ports[0]|tostring)] | unique |
      if length==$expected then .[] else error("API endpoint count differs from expected topology") end'
}
identity() {
  local policy_id binding_id cluster_id
  policy_id="$(k get validatingadmissionpolicy "$policy" -o json |
    jq -er 'select(.spec.failurePolicy=="Fail") | [.metadata.uid,.metadata.generation] |
      select(.[0]|type=="string" and test("^[a-f0-9-]+$")) | select(.[1]|type=="number" and .>=1) | join(":")')" || return 1
  binding_id="$(k get validatingadmissionpolicybinding "$policy" -o json |
    jq -er --arg policy "$policy" 'select(.spec.policyName==$policy and (.spec.validationActions|index("Deny"))!=null) |
      [.metadata.uid,.metadata.generation] | select(.[0]|type=="string" and test("^[a-f0-9-]+$")) |
      select(.[1]|type=="number" and .>=1) | join(":")')" || return 1
  cluster_id="$(k get namespace kube-system -o json | jq -er '.metadata.uid | select(test("^[a-f0-9-]+$"))')" || return 1
  printf '%s:%s:%s\n' "$binding_id" "$policy_id" "$cluster_id"
}
members="$(inventory)"
proof="$(identity)"
assert_unchanged() {
  [[ "$(inventory)" == "$members" && "$(identity)" == "$proof" ]] ||
    { echo 'Admission identity or API server inventory changed during verification' >&2; return 1; }
}
# Match only the denial from this exact policy and binding, not a generic 403
# such as missing operator privileges or a different admission policy.
denial="ValidatingAdmissionPolicy '$policy' with binding '$policy' denied request: Preview NetworkPolicy writer may only be delegated"
subject="$executors:ep-runner-admission-probe-envplane-runner"
probe="envplane-pr-admission-$(openssl rand -hex 8)"
k create namespace "$probe" >&2
cleanup() { base delete namespace "$probe" --wait=false >&2; }
trap cleanup EXIT
assert_denied() {
  local evidence
  if evidence="$(k create "$@" --clusterrole="$policy" --dry-run=server 2>&1)"; then
    return 1
  fi
  if [[ "$evidence" != *"$denial"* ]]; then
    printf '%s\n' "$evidence" >&2
    return 2
  fi
}
verified_members=0
while IFS= read -r endpoint; do
  if (( expected > 1 )); then route=(--server "$endpoint"); fi
  assert_unchanged
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
  [[ "$verified" == true ]] || { echo "Expected denial not enforced by $endpoint" >&2; exit 1; }
  assert_denied rolebinding "$probe" -n "$probe" --serviceaccount="$executors:not-a-managed-runner"
  assert_denied rolebinding "$probe" -n "$executors" --serviceaccount="$subject"
  k create rolebinding "$probe" -n "$probe" --clusterrole="$policy" --serviceaccount="$subject" --dry-run=server >&2
  assert_unchanged
  verified_members=$((verified_members + 1))
  echo "Verified preview admission: $endpoint" >&2
done <<<"$members"
[[ "$verified_members" == "$expected" ]] || { echo 'Not all API servers were verified' >&2; exit 1; }
route=()
assert_unchanged
cleanup
trap - EXIT
printf '%s\n' "$proof"
