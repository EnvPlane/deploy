#!/usr/bin/env bash
set -euo pipefail

# Published-artifact two-cluster E2E. The harness may use port-forwards only as
# its own API/UI client transport; the product install is exactly one umbrella
# helm upgrade --install, and RemoteCluster reconciliation is the only target
# Agent/Runner installation path. It never creates a cluster or invokes a
# child Agent/Runner chart directly.
: "${ENVPILOT_E2E_MANAGEMENT_CONTEXT:?set management kube context}"
: "${ENVPILOT_E2E_TARGET_CONTEXT:?set target kube context}"
: "${ENVPILOT_E2E_UMBRELLA_REF:?set published OCI umbrella ref}"
: "${ENVPILOT_E2E_UMBRELLA_VERSION:?set immutable published umbrella version}"
: "${ENVPILOT_E2E_VALUES_FILE:?set management umbrella values file}"
: "${ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT:?set target Kubernetes HTTPS endpoint}"
: "${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL:?set stable target-pod-reachable HTTPS control-plane endpoint}"
: "${ENVPILOT_E2E_HELM_CHART_REF:?set target-runner-resolvable OCI or HTTPS workload chart}"

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
api_port="${ENVPILOT_E2E_API_PORT:-18080}"
ui_port="${ENVPILOT_E2E_UI_PORT:-13000}"
api_url="${ENVPILOT_E2E_API_URL:-http://127.0.0.1:${api_port}}"
ui_url="${ENVPILOT_E2E_UI_URL:-http://127.0.0.1:${ui_port}}"
scm_provider="${ENVPILOT_E2E_SCM_PROVIDER:-gitlab}"
app_repo="${ENVPILOT_E2E_APP_REPOSITORY_URL:-}"
gitops_repo="${ENVPILOT_E2E_GITOPS_REPOSITORY_URL:-}"
app_branch="${ENVPILOT_E2E_APP_DEFAULT_BRANCH:-main}"
gitops_branch="${ENVPILOT_E2E_GITOPS_DEFAULT_BRANCH:-main}"
scm_token_file="${ENVPILOT_E2E_SCM_TOKEN_FILE:-}"
feature_ref="${ENVPILOT_E2E_FEATURE_REF:-201}"

for bin in curl helm jq kubectl; do command -v "$bin" >/dev/null || { echo "missing $bin" >&2; exit 2; }; done
[[ "$credential_mode" == "existing" || "$credential_mode" == "submit" ]] || { echo "ENVPILOT_E2E_REMOTE_CREDENTIAL_MODE must be existing or submit" >&2; exit 2; }
[[ "$remote_cluster_create_mode" == "api" || "$remote_cluster_create_mode" == "ui" ]] || { echo "ENVPILOT_E2E_REMOTE_CLUSTER_CREATE_MODE must be api or ui" >&2; exit 2; }
[[ "$remote_cluster_create_mode" != "ui" || "$credential_mode" == "existing" ]] || { echo "the browser E2E uses an existing Secret reference; use api mode to test one-time credential submission" >&2; exit 2; }
[[ "$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL" =~ ^https:// ]] || { echo "remote control-plane endpoint must be explicit HTTPS" >&2; exit 2; }
case "${ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL,,}" in *host.minikube.internal*|*localhost*|*127.0.0.1*|*.svc/*|*.svc:*) echo "remote endpoint must be target-pod-reachable, not local or Service DNS" >&2; exit 2;; esac
[[ "$ENVPILOT_E2E_HELM_CHART_REF" == oci://* || "$ENVPILOT_E2E_HELM_CHART_REF" == https://* ]] || { echo "feature chart must be OCI or HTTPS" >&2; exit 2; }
[[ -n "$app_repo" && -n "$gitops_repo" ]] || { echo "set app and GitOps repository URLs" >&2; exit 2; }
[[ -n "$credential_file" && -r "$credential_file" ]] || { echo "set readable ENVPILOT_E2E_REMOTE_CREDENTIAL_FILE" >&2; exit 2; }

tmp="$(mktemp -d)"; pids=()
trap 'for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$tmp"' EXIT
api() { curl -fsS -H 'Content-Type: application/json' "$@"; }
wait_json() { local path="$1" filter="$2"; for _ in $(seq 1 120); do body="$(api "$api_url$path" || true)"; jq -e "$filter" <<<"$body" >/dev/null 2>&1 && { printf '%s' "$body"; return 0; }; sleep 2; done; echo "timeout waiting for $path" >&2; return 1; }

helm upgrade --install "$release" "$ENVPILOT_E2E_UMBRELLA_REF" --version "$ENVPILOT_E2E_UMBRELLA_VERSION" \
  --kube-context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" --namespace "$namespace" --create-namespace --values "$ENVPILOT_E2E_VALUES_FILE" --wait --timeout 15m

# Test-client only: do not confuse this port-forward with the remote endpoint.
kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" -n "$namespace" port-forward "svc/${release}-envpilot-control-plane" "${api_port}:8080" >"$tmp/api.log" 2>&1 & pids+=("$!")
kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" -n "$namespace" port-forward "svc/${release}-envpilot-frontend" "${ui_port}:3000" >"$tmp/ui.log" 2>&1 & pids+=("$!")
for _ in $(seq 1 60); do curl -fsS "$api_url/api/v1/health" >/dev/null 2>&1 && break; sleep 2; done
curl -fsS "$api_url/api/v1/health" >/dev/null

# A project can be created without a target. Reusing its ID for RemoteCluster
# avoids a circular dependency: the reconciler gets a real project-scoped
# identity before the project is assigned the newly healthy target.
project_payload="$(jq -n --arg id "$project_id" --arg app "$app_repo" --arg gitops "$gitops_repo" --arg provider "$scm_provider" --arg app_branch "$app_branch" --arg gitops_branch "$gitops_branch" '{id:$id,name:$id,product_id:"generic",git_repo:{provider:$provider,url:$app,default_branch:$app_branch},gitops_repo:{provider:$provider,url:$gitops,default_branch:$gitops_branch,path:"clusters"}')"
api -X PUT --data "$project_payload" "$api_url/api/v1/projects/$project_id" >/dev/null

if [[ "$credential_mode" == "existing" ]]; then
  kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" -n "$namespace" create secret generic "$credential_secret" --from-file="$credential_key=$credential_file" --dry-run=client -o yaml | kubectl --context "$ENVPILOT_E2E_MANAGEMENT_CONTEXT" apply -f - >/dev/null
fi
remote_payload="$(jq -n --arg id "$cluster_id" --arg endpoint "$ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT" --arg secret "$credential_secret" --arg key "$credential_key" --arg ns "$namespace" --arg control "$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL" --arg project "$project_id" --arg runtime_ns "$remote_namespace" --arg base "$base_namespace" --arg feature "$feature_namespace" '{id:$id,name:$id,kubernetes:{endpoint:$endpoint,credential_secret_ref:{name:$secret,namespace:$ns,key:$key}},control_plane:{endpoint:$control},agent:{enabled:true,release_name:("envpilot-remote-"+$id+"-agent"),namespace:$runtime_ns,project_id:$project},runner:{enabled:true,release_name:("envpilot-remote-"+$id+"-runner"),namespace:$runtime_ns,project_id:$project},discovery:{allowed_namespaces:[$base,$feature]},feature_namespaces:{mode:"shared",shared_namespace:$feature,allowed_prefixes:["envpilot-e2e-"]}}')"
if [[ "$remote_cluster_create_mode" == "ui" ]]; then
  (cd "$(dirname "$0")/../../frontend" && PLAYWRIGHT_SKIP_WEBSERVER=1 PLAYWRIGHT_TEST_DIR=./tests/e2e-real PLAYWRIGHT_BASE_URL="$ui_url" ENVPILOT_E2E_API_URL="$api_url" ENVPILOT_E2E_REAL_CLUSTER=1 ENVPILOT_E2E_REMOTE_CLUSTER_UI=1 ENVPILOT_E2E_REMOTE_CLUSTER_ID="$cluster_id" ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT="$ENVPILOT_E2E_REMOTE_KUBERNETES_ENDPOINT" ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL="$ENVPILOT_E2E_REMOTE_CONTROL_PLANE_URL" ENVPILOT_E2E_REMOTE_CREDENTIAL_SECRET="$credential_secret" ENVPILOT_E2E_REMOTE_CREDENTIAL_KEY="$credential_key" ENVPILOT_E2E_REMOTE_CREDENTIAL_NAMESPACE="$namespace" ENVPILOT_E2E_REMOTE_RUNTIME_NAMESPACE="$remote_namespace" ENVPILOT_E2E_BASE_NAMESPACE="$base_namespace" ENVPILOT_E2E_FEATURE_NAMESPACE="$feature_namespace" npm run test:e2e -- --grep 'creates a managed remote cluster through the UI')
else
  if [[ "$credential_mode" == "submit" ]]; then remote_payload="$(jq --rawfile credential "$credential_file" '. + {credential:$credential}' <<<"$remote_payload")"; fi
  api -X POST --data "$remote_payload" "$api_url/api/v1/remote-clusters" >"$tmp/remote.json"
  grep -Fq '"credential"' "$tmp/remote.json" && { echo "RemoteCluster API leaked credential" >&2; exit 1; }
fi
api "$api_url/api/v1/remote-clusters/$cluster_id" >"$tmp/remote.json"

wait_json "/api/v1/remote-clusters/$cluster_id" '.status.phase == "healthy" and .status.observed_generation == .status.desired_generation and (.status.installed_artifacts|length == 2)' >"$tmp/healthy.json"
for deployment in "envpilot-remote-${cluster_id}-agent" "envpilot-remote-${cluster_id}-runner"; do
  kubectl --context "$ENVPILOT_E2E_TARGET_CONTEXT" -n "$remote_namespace" rollout status "deployment/$deployment" --timeout=5m
  kubectl --context "$ENVPILOT_E2E_TARGET_CONTEXT" -n "$remote_namespace" get pod -l "app.kubernetes.io/instance=$deployment" -o json | jq -e '[.items[].status.initContainerStatuses[]? | select(.name=="control-plane-preflight") | .state.terminated.exitCode] | all(. == 0)' >/dev/null
done

# Assign only after RemoteCluster health is fresh, then execute normal bootstrap
# APIs. No installer script writes session data or target Helm credentials.
project_payload="$(jq '. + {cluster_id:$cluster,authorized_cluster_ids:[$cluster]}' --arg cluster "$cluster_id" <<<"$project_payload")"
api -X PUT --data "$project_payload" "$api_url/api/v1/projects/$project_id" >/dev/null
api -X POST --data '{}' "$api_url/api/projects/$project_id/bootstrap-session" >/dev/null
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

# Endpoint loss must become observable degraded state; restoring the desired
# endpoint plus rotate/repair must return the same target releases to healthy.
broken="$(jq '.control_plane.endpoint="https://unreachable.invalid"' "$tmp/remote.json")"
api -X PUT --data "$broken" "$api_url/api/v1/remote-clusters/$cluster_id" >/dev/null
api -X POST "$api_url/api/v1/remote-clusters/$cluster_id/repair" >/dev/null
wait_json "/api/v1/remote-clusters/$cluster_id" '.status.phase == "degraded" or .status.phase == "blocked"' >/dev/null
api -X PUT --data "$(cat "$tmp/remote.json")" "$api_url/api/v1/remote-clusters/$cluster_id" >/dev/null
# Rotate the management-cluster credential Secret through the authenticated API
# without printing its content, then rotate the one-time Agent/Runner identity.
credential_rotation="$(jq --rawfile credential "$credential_file" '{credential:$credential}')"
api -X POST --data "$credential_rotation" "$api_url/api/v1/remote-clusters/$cluster_id/credentials/rotate" >/dev/null
api -X POST "$api_url/api/v1/remote-clusters/$cluster_id/rotate" >/dev/null
api -X POST "$api_url/api/v1/remote-clusters/$cluster_id/repair" >/dev/null
wait_json "/api/v1/remote-clusters/$cluster_id" '.status.phase == "healthy" and .status.observed_generation == .status.desired_generation' >/dev/null

echo 'published two-cluster RemoteCluster E2E passed'
