#!/usr/bin/env bash
set -euo pipefail

# Published-artifact two-cluster E2E. Both clusters and the private HTTPS
# management endpoint are external prerequisites. The product install is exactly
# one umbrella helm upgrade --install; RemoteCluster reconciliation is the only
# Agent/Runner installation path. This harness never starts clusters, tunnels,
# port-forwards, or child Agent/Runner chart commands.
: "${ENVPILOT_E2E_MANAGEMENT_CONTEXT:?set management kube context}"
: "${ENVPILOT_E2E_TARGET_CONTEXT:?set target kube context}"
: "${ENVPILOT_E2E_UMBRELLA_REF:?set published OCI umbrella ref}"
: "${ENVPILOT_E2E_UMBRELLA_VERSION:?set immutable published umbrella version}"
: "${ENVPILOT_E2E_VALUES_FILE:?set management umbrella values file}"
: "${ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT:?set target Kubernetes HTTPS endpoint}"
: "${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL:?set stable target-pod-reachable HTTPS control-plane endpoint}"
: "${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_TLS_SERVER_NAME:?set private endpoint TLS server name}"
: "${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_FILE:?set private endpoint CA PEM file}"
: "${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_ROTATED_CA_FILE:?set rotated private endpoint CA PEM file}"
: "${ENVPILOT_E2E_HELM_CHART_REF:?set target-runner-resolvable OCI or HTTPS workload chart}"
: "${ENVPILOT_E2E_API_URL:?set stable management API URL for the E2E client}"
: "${ENVPILOT_E2E_UI_URL:?set stable management UI URL for browser E2E}"

namespace="${ENVPILOT_E2E_NAMESPACE:-envpilot}"
release="${ENVPILOT_E2E_RELEASE:-envpilot}"
project_id="${ENVPILOT_E2E_PROJECT_ID:-published-remote-e2e}"
cluster_id="${ENVPILOT_E2E_REMOTE_CLUSTER_ID:-$project_id}"
remote_namespace="${ENVPILOT_E2E_REMOTE_NAMESPACE:-envpilot-system}"
base_namespace="${ENVPILOT_E2E_BASE_NAMESPACE:-envpilot-e2e-base}"
feature_namespace="${ENVPILOT_E2E_FEATURE_NAMESPACE:-envpilot-e2e-feature}"
environment_id="${ENVPILOT_E2E_ENVIRONMENT_ID:-${project_id}-full}"
credential_mode="${ENVPILOT_E2E_REMOTE_CREDENTIAL_MODE:-existing}" # existing|submit
remote_cluster_create_mode="${ENVPILOT_E2E_REMOTE_CLUSTER_CREATE_MODE:-api}" # api|ui
credential_secret="${ENVPILOT_E2E_REMOTE_CREDENTIAL_SECRET:-${cluster_id}-kubeconfig}"
credential_key="${ENVPILOT_E2E_REMOTE_CREDENTIAL_KEY:-kubeconfig}"
credential_file="${ENVPILOT_E2E_REMOTE_CREDENTIAL_FILE:-}"
api_url="${ENVPILOT_E2E_API_URL%/}"
ui_url="${ENVPILOT_E2E_UI_URL%/}"
control_plane_ca_secret="${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_SECRET:-${cluster_id}-management-ca}"
control_plane_ca_key="${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_KEY:-ca.crt}"
target_control_plane_ca_secret="${ENVPILOT_E2E_REMOTE_TARGET_CA_SECRET:-${cluster_id}-control-plane-ca}"
target_control_plane_ca_key="${ENVPILOT_E2E_REMOTE_TARGET_CA_KEY:-$control_plane_ca_key}"
scm_provider="${ENVPILOT_E2E_SCM_PROVIDER:-gitlab}"
app_repo="${ENVPILOT_E2E_APP_REPOSITORY_URL:-}"
gitops_repo="${ENVPILOT_E2E_GITOPS_REPOSITORY_URL:-}"
app_branch="${ENVPILOT_E2E_APP_DEFAULT_BRANCH:-main}"
gitops_branch="${ENVPILOT_E2E_GITOPS_DEFAULT_BRANCH:-main}"
scm_token_file="${ENVPILOT_E2E_SCM_TOKEN_FILE:-}"
feature_ref="${ENVPILOT_E2E_FEATURE_REF:-201}"
runtime_stability_wait_seconds="${ENVPILOT_E2E_REMOTE_RUNTIME_STABILITY_WAIT_SECONDS:-35}"

for bin in curl helm jq kubectl; do command -v "$bin" >/dev/null || { echo "missing $bin" >&2; exit 2; }; done
[[ "$credential_mode" == "existing" || "$credential_mode" == "submit" ]] || { echo "ENVPILOT_E2E_REMOTE_CREDENTIAL_MODE must be existing or submit" >&2; exit 2; }
[[ "$remote_cluster_create_mode" == "api" || "$remote_cluster_create_mode" == "ui" ]] || { echo "ENVPILOT_E2E_REMOTE_CLUSTER_CREATE_MODE must be api or ui" >&2; exit 2; }
[[ "$remote_cluster_create_mode" != "ui" || "$credential_mode" == "existing" ]] || { echo "the browser E2E uses an existing Secret reference; use api mode to test one-time credential submission" >&2; exit 2; }
[[ "$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL" =~ ^https:// ]] || { echo "remote control-plane endpoint must be explicit HTTPS" >&2; exit 2; }
case "${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL,,}" in *host.minikube.internal*|*localhost*|*127.0.0.1*|*.svc/*|*.svc:*) echo "remote endpoint must be target-pod-reachable, not local or Service DNS" >&2; exit 2;; esac
[[ "$ENVPILOT_E2E_HELM_CHART_REF" == oci://* || "$ENVPILOT_E2E_HELM_CHART_REF" == https://* ]] || { echo "feature chart must be OCI or HTTPS" >&2; exit 2; }
[[ -n "$app_repo" && -n "$gitops_repo" ]] || { echo "set app and GitOps repository URLs" >&2; exit 2; }
[[ -n "$credential_file" && -r "$credential_file" ]] || { echo "set readable ENVPILOT_E2E_REMOTE_CREDENTIAL_FILE" >&2; exit 2; }
[[ -r "$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_FILE" ]] || { echo "set readable ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_FILE" >&2; exit 2; }
[[ -r "$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_ROTATED_CA_FILE" ]] || { echo "set readable ENVPILOT_E2E_REMOTE_CONTROL_PLANE_ROTATED_CA_FILE" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
api() { curl -fsS -H 'Content-Type: application/json' "$@"; }
wait_json() { local path="$1" filter="$2"; for _ in $(seq 1 120); do body="$(api "$api_url$path" || true)"; jq -e "$filter" <<<"$body" >/dev/null 2>&1 && { printf '%s' "$body"; return 0; }; sleep 2; done; echo "timeout waiting for $path" >&2; return 1; }

helm upgrade --install "$release" "$ENVPILOT_E2E_UMBRELLA_REF" --version "$ENVPILOT_E2E_UMBRELLA_VERSION" \
  --kube-context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" --namespace "$namespace" --create-namespace --values "$ENVPILOT_E2E_VALUES_FILE" --wait --timeout 15m

# The control-plane Lease must be created in the same non-default management
# namespace as this umbrella release. This catches a missing POD_NAMESPACE (or
# an accidental default namespace fallback) before the RemoteCluster flow
# reports a less useful reconciliation timeout.
leader_lease="envpilot-remote-cluster-reconciler"
leader_identity=""
for _ in $(seq 1 60); do
  leader_identity="$(kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" -n "$namespace" get lease "$leader_lease" -o json 2>/dev/null | jq -r '.spec.holderIdentity // ""' || true)"
  [[ -n "$leader_identity" ]] && break
  sleep 2
done
[[ -n "$leader_identity" ]] || {
  echo "remote cluster reconciler did not acquire Lease $namespace/$leader_lease; verify POD_NAMESPACE or remoteClusterReconciler.leaderElection.namespace and matching Role/RoleBinding" >&2
  exit 1
}

# The E2E client uses a stable management API/UI address provided by the test
# environment. It deliberately cannot make a port-forward look like a remote
# endpoint contract.
for _ in $(seq 1 60); do curl -fsS "$api_url/api/v1/health" >/dev/null 2>&1 && break; sleep 2; done
curl -fsS "$api_url/api/v1/health" >/dev/null

# The private CA is deliberately created as a Secret in the management
# namespace. The API stores only this reference, and managed RemoteCluster
# reconciliation copies it to the target runtime namespace by its safe
# managementCopy contract.
kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" -n "$namespace" create secret generic "$control_plane_ca_secret" \
  --from-file="$control_plane_ca_key=$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_FILE" --dry-run=client -o yaml | \
  kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" apply -f - >/dev/null
management_profile="$(jq -n \
  --arg endpoint "$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL" \
  --arg server_name "$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_TLS_SERVER_NAME" \
  --arg secret "$control_plane_ca_secret" --arg namespace "$namespace" --arg key "$control_plane_ca_key" \
  '{endpoint:$endpoint,tls:{server_name:$server_name,ca_secret_ref:{name:$secret,namespace:$namespace,key:$key}}}')"
api -X PUT --data "$management_profile" "$api_url/api/v1/management-endpoint-profile" >"$tmp/management-profile.json"
grep -Eiq 'certificate|credential|kubeconfig|token' "$tmp/management-profile.json" && { echo "management endpoint API leaked private material" >&2; exit 1; }

# This comes from the published API-managed endpoint profile contract. It
# proves the management release advertises the same private HTTPS endpoint
# before the UI requests remote reconciliation.
capabilities="$(api "$api_url/api/v1/capabilities")"
jq -e --arg endpoint "$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL" '
  .remoteControlPlane.state == "ready" and .remoteControlPlane.endpoint == $endpoint
' <<<"$capabilities" >/dev/null || {
  echo "published management API does not advertise the saved remote control-plane endpoint profile" >&2
  exit 1
}

# A project can be created without a target. Reusing its ID for RemoteCluster
# avoids a circular dependency: the reconciler gets a real project-scoped
# identity before the project is assigned the newly healthy target.
project_payload="$(jq -n --arg id "$project_id" --arg app "$app_repo" --arg gitops "$gitops_repo" --arg provider "$scm_provider" --arg app_branch "$app_branch" --arg gitops_branch "$gitops_branch" '{id:$id,name:$id,product_id:"generic",git_repo:{provider:$provider,url:$app,default_branch:$app_branch},gitops_repo:{provider:$provider,url:$gitops,default_branch:$gitops_branch,path:"clusters"}')"
api -X PUT --data "$project_payload" "$api_url/api/v1/projects/$project_id" >/dev/null

if [[ "$credential_mode" == "existing" ]]; then
  kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" -n "$namespace" create secret generic "$credential_secret" --from-file="$credential_key=$credential_file" --dry-run=client -o yaml | kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" apply -f - >/dev/null
fi
remote_payload="$(jq -n --arg id "$cluster_id" --arg endpoint "$ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT" --arg secret "$credential_secret" --arg key "$credential_key" --arg ns "$namespace" --arg source_secret "$control_plane_ca_secret" --arg source_key "$control_plane_ca_key" --arg target_secret "$target_control_plane_ca_secret" --arg target_key "$target_control_plane_ca_key" --arg project "$project_id" --arg runtime_ns "$remote_namespace" --arg base "$base_namespace" --arg feature "$feature_namespace" '{id:$id,name:$id,kubernetes:{endpoint:$endpoint,credential_secret_ref:{name:$secret,namespace:$ns,key:$key}},control_plane:{trust:{mode:"managementCopy",source_secret_ref:{name:$source_secret,namespace:$ns,key:$source_key},target_secret_ref:{name:$target_secret,namespace:$runtime_ns,key:$target_key}}},agent:{enabled:true,release_name:("envpilot-remote-"+$id+"-agent"),namespace:$runtime_ns,project_id:$project},runner:{enabled:true,release_name:("envpilot-remote-"+$id+"-runner"),namespace:$runtime_ns,project_id:$project},discovery:{allowed_namespaces:[$base,$feature]},feature_namespaces:{mode:"shared",shared_namespace:$feature,allowed_prefixes:["envpilot-e2e-"]}}')"
if [[ "$remote_cluster_create_mode" == "ui" ]]; then
	(cd "$(dirname "$0")/../../frontend" && PLAYWRIGHT_SKIP_WEBSERVER=1 PLAYWRIGHT_TEST_DIR=./tests/e2e-real PLAYWRIGHT_BASE_URL="$ui_url" ENVPILOT_E2E_API_URL="$api_url" ENVPILOT_E2E_REAL_CLUSTER=1 ENVPILOT_E2E_REMOTE_CLUSTER_UI=1 ENVPILOT_E2E_REMOTE_CLUSTER_ID="$cluster_id" ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT="$ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT" ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL="$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL" ENVPILOT_E2E_REMOTE_CONTROL_PLANE_TLS_SERVER_NAME="$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_TLS_SERVER_NAME" ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_SECRET="$control_plane_ca_secret" ENVPILOT_E2E_REMOTE_CONTROL_PLANE_CA_KEY="$control_plane_ca_key" ENVPILOT_E2E_REMOTE_TARGET_CA_SECRET="$target_control_plane_ca_secret" ENVPILOT_E2E_REMOTE_TARGET_CA_KEY="$target_control_plane_ca_key" ENVPILOT_E2E_REMOTE_CREDENTIAL_SECRET="$credential_secret" ENVPILOT_E2E_REMOTE_CREDENTIAL_KEY="$credential_key" ENVPILOT_E2E_REMOTE_CREDENTIAL_NAMESPACE="$namespace" ENVPILOT_E2E_REMOTE_RUNTIME_NAMESPACE="$remote_namespace" ENVPILOT_E2E_BASE_NAMESPACE="$base_namespace" ENVPILOT_E2E_FEATURE_NAMESPACE="$feature_namespace" npm run test:e2e -- --grep 'creates a managed remote cluster through the UI')
else
  if [[ "$credential_mode" == "submit" ]]; then remote_payload="$(jq --rawfile credential "$credential_file" '. + {credential:$credential}' <<<"$remote_payload")"; fi
  api -X POST --data "$remote_payload" "$api_url/api/v1/remote-clusters" >"$tmp/remote.json"
  grep -Fq '"credential"' "$tmp/remote.json" && { echo "RemoteCluster API leaked credential" >&2; exit 1; }
fi
api "$api_url/api/v1/remote-clusters/$cluster_id" >"$tmp/remote.json"

wait_json "/api/v1/remote-clusters/$cluster_id" '
  .status.phase == "healthy" and
  .status.observed_generation == .status.desired_generation and
  .status.management_endpoint_profile_observed_generation == .status.management_endpoint_profile_desired_generation and
  .status.endpoint_preflight.agent.code == "passed" and
  .status.endpoint_preflight.runner.code == "passed" and
  (.status.installed_artifacts|length == 2)
' >"$tmp/healthy.json"
kubectl --context "$ENVPILOT_E2E_TARGET_CONTEXT" -n "$remote_namespace" get secret "$target_control_plane_ca_secret" -o json | jq -e \
  --arg cluster "$cluster_id" '.metadata.labels["envpilot.io/managed-by"] == "remote-cluster-reconciler" and .metadata.labels["envpilot.io/remote-cluster-id"] == $cluster and .metadata.labels["envpilot.io/purpose"] == "control-plane-trust"' >/dev/null
for deployment in "envpilot-remote-${cluster_id}-agent" "envpilot-remote-${cluster_id}-runner"; do
  kubectl --context "$ENVPILOT_E2E_TARGET_CONTEXT" -n "$remote_namespace" rollout status "deployment/$deployment" --timeout=5m
  kubectl --context "$ENVPILOT_E2E_TARGET_CONTEXT" -n "$remote_namespace" get pod -l "app.kubernetes.io/instance=$deployment" -o json | jq -e '[.items[].status.initContainerStatuses[]? | select(.name=="control-plane-preflight") | .state.terminated.exitCode] | all(. == 0)' >/dev/null
done

# Assign only after RemoteCluster health is fresh, then execute normal bootstrap
# APIs. No installer script writes session data or target Helm credentials.
project_payload="$(jq '. + {cluster_id:$cluster,authorized_cluster_ids:[$cluster]}' --arg cluster "$cluster_id" <<<"$project_payload")"
api -X PUT --data "$project_payload" "$api_url/api/v1/projects/$project_id" >/dev/null
api -X POST --data '{}' "$api_url/api/projects/$project_id/bootstrap-session" >/dev/null

# Reconciliation/Helm installation has returned before this point. Require two
# independent fresh status observations before dispatching an Environment: the
# later create result proves authenticated Runner command polling continues
# without a test-client port-forward or installer process in the target cluster.
assert_remote_runtime_after_installer_exit() {
  wait_json "/api/projects/$project_id/bootstrap-session/agent-status" '(.status == "connected" or .status == "online") and ((.effectiveStatus // .status) == "connected" or (.effectiveStatus // .status) == "online")' >/dev/null
  wait_json "/api/projects/$project_id/bootstrap-session/runner-status" '(.status == "connected" or .status == "online")' >/dev/null
  sleep "$runtime_stability_wait_seconds"
  wait_json "/api/projects/$project_id/bootstrap-session/agent-status" '(.status == "connected" or .status == "online") and ((.effectiveStatus // .status) == "connected" or (.effectiveStatus // .status) == "online")' >/dev/null
  wait_json "/api/projects/$project_id/bootstrap-session/runner-status" '(.status == "connected" or .status == "online")' >/dev/null
}
assert_remote_runtime_after_installer_exit
scm_token="$(awk '/^(glpat-|ghp_|github_pat_)/{print; exit}' "${ENVPILOT_E2E_SCM_TOKEN_FILE:-/dev/null}")"
[[ -n "$scm_token" ]] || { echo "set ENVPILOT_E2E_SCM_TOKEN_FILE for bootstrap validation" >&2; exit 2; }
scm_payload="$(jq -n --arg provider "$scm_provider" --arg app "$app_repo" --arg gitops "$gitops_repo" --arg branch "$app_branch" --arg gitops_branch "$gitops_branch" --arg token "$scm_token" '{provider:$provider,appRepoUrl:$app,gitopsRepoUrl:$gitops,appDefaultBranch:$branch,gitopsDefaultBranch:$gitops_branch,authMethod:"oauth",oauthToken:$token}')"
api -X POST --data "$scm_payload" "$api_url/api/projects/$project_id/bootstrap-session/validate-scm" | jq -e '.valid == true' >/dev/null
bootstrap_patch="$(jq -n --arg base "$base_namespace" --arg ref "$ENVPILOT_E2E_HELM_CHART_REF" --arg feature "$feature_namespace" '{step_data:{selectedBaseNamespaces:[$base],deployment:{backend:"helm_direct",helmDirect:{chartRef:$ref,namespaceMode:"shared",namespacePattern:$feature,releaseNamePattern:"envpilot-e2e",wait:true,createNamespace:false}}}}')"
api -X PATCH --data "$bootstrap_patch" "$api_url/api/projects/$project_id/bootstrap-session" >/dev/null
api -X POST --data '{}' "$api_url/api/projects/$project_id/bootstrap-session/resource-scan/start" >/dev/null
wait_json "/api/projects/$project_id/bootstrap-session/agent-status" '.resourceScanStatus == "completed"' >/dev/null
api -X POST --data '{}' "$api_url/api/projects/$project_id/bootstrap-session/helm-direct/preflight" >/dev/null
wait_json "/api/projects/$project_id/bootstrap-session" '.data.helmDirectChartValidation.status == "succeeded"' >/dev/null
api -X POST --data '{}' "$api_url/api/projects/$project_id/bootstrap-session/compile" >/dev/null
wait_json "/api/v1/projects/$project_id" '.deployment_readiness.ready == true' >/dev/null

# Browser Environment creation/delete uses the same published frontend API;
# the Playwright test also asserts no client errors and cleanup convergence.
(cd "$(dirname "$0")/../../frontend" && PLAYWRIGHT_SKIP_WEBSERVER=1 PLAYWRIGHT_TEST_DIR=./tests/e2e-real PLAYWRIGHT_BASE_URL="$ui_url" ENVPILOT_E2E_API_URL="$api_url" ENVPILOT_E2E_REAL_CLUSTER=1 ENVPILOT_E2E_RUN_LIFECYCLE=1 ENVPILOT_E2E_KEEP_ENVIRONMENT=1 ENVPILOT_E2E_PROJECT_ID="$project_id" ENVPILOT_E2E_ENVIRONMENT_ID="$environment_id" npm run test:e2e -- --grep 'creates a real full environment through the UI')
environment="$(api "$api_url/api/v1/environments/$environment_id")"
release_name="$(jq -er '.helmReleaseName' <<<"$environment")"
target_namespace="$(jq -er '.targetNamespace' <<<"$environment")"
helm --kube-context "$ENVPILOT_E2E_TARGET_CONTEXT" -n "$target_namespace" status "$release_name" >/dev/null
control_release="$(helm --kube-context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" list --all-namespaces -o json | jq -r --arg release "$release_name" '.[] | select(.name == $release) | .name')"
[[ -z "$control_release" ]] || { echo "feature release unexpectedly exists in the management cluster" >&2; exit 1; }
api -X DELETE "$api_url/api/v1/environments/$environment_id?force=true" >/dev/null
wait_json "/api/v1/environments/$environment_id" '(.status == "terminated") or false' >/dev/null || true

# DNS failure must become an observable remote target degradation. It is
# injected by changing the API-managed ManagementEndpointProfile, never by an
# invalid per-cluster endpoint override.
broken_profile="$(jq '.endpoint="https://does-not-resolve.invalid"' "$tmp/management-profile.json")"
api -X PUT --data "$broken_profile" "$api_url/api/v1/management-endpoint-profile" >/dev/null
api -X POST "$api_url/api/v1/remote-clusters/$cluster_id/repair" >/dev/null
wait_json "/api/v1/remote-clusters/$cluster_id" '(.status.phase == "degraded" or .status.phase == "blocked") and ((.status.endpoint_preflight.agent.code == "dns_failed") or (.status.endpoint_preflight.runner.code == "dns_failed"))' >/dev/null

# Restore the stable endpoint and rotate the CA trust source. The externally
# provisioned endpoint must already present a certificate chaining to the
# rotated CA. Raw PEM never enters an API request or log.
api -X PUT --data "$management_profile" "$api_url/api/v1/management-endpoint-profile" >"$tmp/restored-management-profile.json"
kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" -n "$namespace" create secret generic "$control_plane_ca_secret" \
  --from-file="$control_plane_ca_key=$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_ROTATED_CA_FILE" --dry-run=client -o yaml | \
  kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" apply -f - >/dev/null
trust_before="$(jq -r '.status.trust.revision // ""' "$tmp/healthy.json")"
api -X POST "$api_url/api/v1/remote-clusters/$cluster_id/repair" >/dev/null
recovered="$(wait_json "/api/v1/remote-clusters/$cluster_id" '
  .status.phase == "healthy" and
  .status.observed_generation == .status.desired_generation and
  .status.management_endpoint_profile_observed_generation == .status.management_endpoint_profile_desired_generation and
  .status.endpoint_preflight.agent.code == "passed" and
  .status.endpoint_preflight.runner.code == "passed" and
  (.status.trust.revision // "") != ""
')"
trust_after="$(jq -r '.status.trust.revision // ""' <<<"$recovered")"
[[ "$trust_after" != "$trust_before" ]] || { echo "private CA rotation did not advance target trust revision" >&2; exit 1; }

echo 'published two-cluster RemoteCluster E2E passed'
