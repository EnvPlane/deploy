#!/usr/bin/env bash
# Provision and exercise one disposable, deploy-ready EnvPilot project across
# two local minikube profiles. It uses only public control-plane APIs and the
# real Agent/Runner Helm charts; it never seeds bootstrap-session storage or
# writes credentials to the repository.
#
# The project, Agent and Runner remain after a successful run so the fixture is
# reusable. The feature environment and Helm release are removed by default.
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="${ENVPILOT_WORKSPACE_ROOT:-$(cd "$DEPLOY_ROOT/.." && pwd)}"
API_URL="${ENVPILOT_E2E_API_URL:-http://127.0.0.1:18080}"
CONTROL_PROFILE="${ENVPILOT_CONTROL_MINIKUBE_PROFILE:-envpilot}"
TARGET_PROFILE="${ENVPILOT_E2E_TARGET_MINIKUBE_PROFILE:-bethunder-local}"
CLUSTER_ID="${ENVPILOT_E2E_CLUSTER_ID:-$TARGET_PROFILE}"

PROJECT_ID="${ENVPILOT_E2E_PROJECT_ID:-envpilot-e2e-fixture}"
PROJECT_NAME="${ENVPILOT_E2E_PROJECT_NAME:-EnvPilot local E2E fixture}"
BASE_NAMESPACE="${ENVPILOT_E2E_BASE_NAMESPACE:-envpilot-e2e-base}"
PR_NUMBER="${ENVPILOT_E2E_PR_NUMBER:-101}"
FEATURE_NAMESPACE="${ENVPILOT_E2E_FEATURE_NAMESPACE:-envpilot-pr-${PR_NUMBER}}"
ENVIRONMENT_ID="${ENVPILOT_E2E_ENVIRONMENT_ID:-envpilot-e2e-full-${PR_NUMBER}}"
AGENT_NAMESPACE="${ENVPILOT_E2E_AGENT_NAMESPACE:-envpilot}"
RUNNER_NAMESPACE="${ENVPILOT_E2E_RUNNER_NAMESPACE:-envpilot}"
AGENT_ID="${ENVPILOT_E2E_AGENT_ID:-envpilot-e2e-agent}"
AGENT_RELEASE="${ENVPILOT_E2E_AGENT_RELEASE:-envpilot-e2e-agent}"
RUNNER_RELEASE="${ENVPILOT_E2E_RUNNER_RELEASE:-envpilot-e2e-runner}"
CHART_PORT="${ENVPILOT_E2E_CHART_PORT:-18082}"
CHART_ARCHIVE_NAME=""
SCM_PROVIDER="${ENVPILOT_E2E_SCM_PROVIDER:-gitlab}"
# These are the canonical repositories reachable by the local E2E GitLab
# credential. The old bh/... aliases return 404 for that credential. Keep both
# values overridable so a different installation can inject its own pair.
APP_REPOSITORY_URL="${ENVPILOT_E2E_APP_REPOSITORY_URL:-https://gitlab.com/betario/cms-team/cms.git}"
GITOPS_REPOSITORY_URL="${ENVPILOT_E2E_GITOPS_REPOSITORY_URL:-https://gitlab.com/betario/devops/gitops/fluxcd/clusters.git}"
APP_DEFAULT_BRANCH="${ENVPILOT_E2E_APP_DEFAULT_BRANCH:-develop}"
GITOPS_DEFAULT_BRANCH="${ENVPILOT_E2E_GITOPS_DEFAULT_BRANCH:-main}"
SCM_TOKEN="${ENVPILOT_E2E_SCM_TOKEN:-}"
SCM_TOKEN_FILE="${ENVPILOT_E2E_SCM_TOKEN_FILE:-}"
USE_UI="${ENVPILOT_E2E_USE_UI:-false}"
UI_BASE_URL="${ENVPILOT_E2E_UI_BASE_URL:-}"
KEEP_ENVIRONMENT=false

for arg in "$@"; do
  case "$arg" in
    --keep-environment) KEEP_ENVIRONMENT=true ;;
    *) echo "usage: $0 [--keep-environment]" >&2; exit 2 ;;
  esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for bin in awk curl helm jq kubectl minikube python3 sed; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required"
done
if [[ -z "$SCM_TOKEN" && -n "$SCM_TOKEN_FILE" ]]; then
  [[ -r "$SCM_TOKEN_FILE" ]] || die "SCM token file is not readable: $SCM_TOKEN_FILE"
  case "$SCM_PROVIDER" in
    gitlab)
      SCM_TOKEN="$(awk '/^glpat-/{print; exit}' "$SCM_TOKEN_FILE")"
      ;;
    github)
      SCM_TOKEN="$(awk '/^(ghp_|github_pat_)/{print; exit}' "$SCM_TOKEN_FILE")"
      ;;
  esac
fi
[[ -n "$SCM_TOKEN" ]] || die "set ENVPILOT_E2E_SCM_TOKEN or ENVPILOT_E2E_SCM_TOKEN_FILE for the normal SCM validation path"
[[ "$SCM_PROVIDER" == "github" || "$SCM_PROVIDER" == "gitlab" ]] || die "ENVPILOT_E2E_SCM_PROVIDER must be github or gitlab"

CHART_DIR="$DEPLOY_ROOT/deploy/helm/envpilot-e2e-workload"
AGENT_CHART="$DEPLOY_ROOT/deploy/helm/envpilot-agent"
RUNNER_CHART="$DEPLOY_ROOT/deploy/helm/envpilot-runner"
[[ -d "$CHART_DIR" && -d "$AGENT_CHART" && -d "$RUNNER_CHART" ]] || die "required Helm chart is missing"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/envpilot-e2e.XXXXXX")"
chart_server_pid=""

cleanup() {
  local status=$?
  if [[ -n "$chart_server_pid" ]] && kill -0 "$chart_server_pid" >/dev/null 2>&1; then
    kill "$chart_server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$temp_dir"
  if [[ "$KEEP_ENVIRONMENT" != true && $status -eq 0 ]]; then
    cleanup_environment || true
  fi
  "$DEPLOY_ROOT/scripts/minikube-agent-access.sh" stop >/dev/null 2>&1 || true
  exit "$status"
}
trap cleanup EXIT

api_get() {
  curl --fail --silent --show-error "$API_URL$1"
}

api_json() {
  local method="$1"
  local path="$2"
  local payload="$3"
  curl --fail --silent --show-error \
    -X "$method" \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    "$API_URL$path"
}

wait_for() {
  local description="$1"
  local attempts="$2"
  local command="$3"
  local output=""
  for _ in $(seq 1 "$attempts"); do
    if output="$(eval "$command")"; then
      printf '%s' "$output"
      return 0
    fi
    sleep 2
  done
  die "timed out waiting for $description"
}

cleanup_environment() {
  log "Cleaning up disposable environment $ENVIRONMENT_ID"
  if api_get "/api/v1/environments/$ENVIRONMENT_ID" >/dev/null 2>&1; then
    api_json DELETE "/api/v1/environments/$ENVIRONMENT_ID" '' >/dev/null || return 0
    wait_for "Runner delete result" 90 "[[ \$(api_get /api/v1/environments/$ENVIRONMENT_ID | jq -r .status) == terminated ]]" >/dev/null || true
  fi
  kubectl --context "$TARGET_PROFILE" delete namespace "$FEATURE_NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
}

validate_scm() {
  log "Validating the fixture SCM repositories without persisting the credential"
  local payload result
  payload="$(jq -n \
    --arg provider "$SCM_PROVIDER" \
    --arg app "$APP_REPOSITORY_URL" \
    --arg gitops "$GITOPS_REPOSITORY_URL" \
    --arg appBranch "$APP_DEFAULT_BRANCH" \
    --arg gitopsBranch "$GITOPS_DEFAULT_BRANCH" \
    --arg token "$SCM_TOKEN" \
    '{provider:$provider, appRepoUrl:$app, gitopsRepoUrl:$gitops, appDefaultBranch:$appBranch, gitopsDefaultBranch:$gitopsBranch, authMethod:"oauth", oauthToken:$token}')"
  result="$(api_json POST "/api/projects/$PROJECT_ID/bootstrap-session/validate-scm" "$payload")"
  if ! jq -e '.valid == true and .appRepositoryReadable == true and .gitopsRepositoryWritable == true and .hasAuthenticationValidated == true' >/dev/null <<<"$result"; then
    local diagnostics
    diagnostics="$(jq -r '[(.errors // [])[] | [(.field // "scm"), (.code // "validation_error"), (.message // "validation failed")] | join(": ")] | join("; ")' <<<"$result")"
    [[ -n "$diagnostics" ]] || diagnostics="validation returned invalid repository or permission state"
    die "SCM preflight failed for provider=$SCM_PROVIDER app=$APP_REPOSITORY_URL@$APP_DEFAULT_BRANCH gitops=$GITOPS_REPOSITORY_URL@$GITOPS_DEFAULT_BRANCH: $diagnostics"
  fi
  log "SCM preflight passed: provider=$SCM_PROVIDER appReadable=true gitopsWritable=true"
}

ensure_project_and_session() {
  log "Creating or updating disposable project $PROJECT_ID"
  local project_payload
  project_payload="$(jq -n \
    --arg id "$PROJECT_ID" --arg name "$PROJECT_NAME" --arg cluster "$CLUSTER_ID" \
    --arg provider "$SCM_PROVIDER" --arg app "$APP_REPOSITORY_URL" --arg appBranch "$APP_DEFAULT_BRANCH" \
    --arg gitops "$GITOPS_REPOSITORY_URL" --arg gitopsBranch "$GITOPS_DEFAULT_BRANCH" --arg base "$BASE_NAMESPACE" \
    '{id:$id,name:$name,product_id:"generic",cluster_id:$cluster,
      git_repo:{provider:$provider,url:$app,default_branch:$appBranch},
      gitops_repo:{provider:$provider,url:$gitops,default_branch:$gitopsBranch,path:"clusters"},
      base_env_config:{environment_id:"envpilot-e2e-base",namespace:$base,services:[{name:"e2e-base-workload",namespace:$base}]},
      cost_policy:{default_ttl_hours:1}}')"
  api_json PUT "/api/v1/projects/$PROJECT_ID" "$project_payload" >/dev/null
  api_json POST "/api/projects/$PROJECT_ID/bootstrap-session" '{}' >/dev/null
}

install_agent() {
  log "Installing Agent in target profile $TARGET_PROFILE"
  local token payload
  payload="$(jq -n --arg cluster "$CLUSTER_ID" --arg agent "$AGENT_ID" --arg ns "$AGENT_NAMESPACE" --arg release "$AGENT_RELEASE" '{clusterId:$cluster,agentId:$agent,agentNamespace:$ns,releaseName:$release}')"
  token="$(api_json POST "/api/projects/$PROJECT_ID/bootstrap-session/agent-token" "$payload" | jq -er '.registrationToken')"
  kubectl --context "$TARGET_PROFILE" create namespace "$AGENT_NAMESPACE" --dry-run=client -o yaml | kubectl --context "$TARGET_PROFILE" apply -f - >/dev/null
  kubectl --context "$TARGET_PROFILE" -n "$AGENT_NAMESPACE" create secret generic envpilot-e2e-agent-bootstrap \
    --from-literal=registration-token="$token" --dry-run=client -o yaml | kubectl --context "$TARGET_PROFILE" apply -f - >/dev/null
  helm upgrade --install "$AGENT_RELEASE" "$AGENT_CHART" \
    --kube-context "$TARGET_PROFILE" --namespace "$AGENT_NAMESPACE" \
    --set-string fullnameOverride="$AGENT_ID" \
    --set-string image.repository=envpilot/agent --set-string image.tag=local --set image.pullPolicy=Never \
    --set-string controlPlane.url="http://host.minikube.internal:18080" \
    --set-string controlPlane.existingSecret=envpilot-e2e-agent-bootstrap \
    --set-string cluster.id="$CLUSTER_ID" --set-string bootstrap.projectId="$PROJECT_ID" --set-string agent.id="$AGENT_ID" \
    --set-string "watch.namespaces[0]=$BASE_NAMESPACE" \
    --set agent.authPersistence.createClaim=false --set installValidation.enabled=false >/dev/null
  kubectl --context "$TARGET_PROFILE" -n "$AGENT_NAMESPACE" rollout restart "deployment/$AGENT_ID" >/dev/null
  kubectl --context "$TARGET_PROFILE" -n "$AGENT_NAMESPACE" rollout status "deployment/$AGENT_ID" --timeout=180s
  wait_for "Agent connection" 90 "[[ \$(api_get /api/projects/$PROJECT_ID/bootstrap-session/agent-status | jq -r .status) == connected ]]" >/dev/null
}

runner_tokens() {
  local instructions payload command token config
  payload="$(jq -n --arg cluster "$CLUSTER_ID" --arg ns "$RUNNER_NAMESPACE" --arg release "$RUNNER_RELEASE" '{deploymentMode:"helm",clusterId:$cluster,runnerNamespace:$ns,releaseName:$release}')"
  instructions="$(api_json POST "/api/projects/$PROJECT_ID/bootstrap-session/runner-deployment-instructions" "$payload")"
  command="$(jq -r '.bootstrapSecretCommand // ""' <<<"$instructions")"
  if [[ "$command" == *'[masked]'* ]]; then
    payload="$(jq -n --arg cluster "$CLUSTER_ID" --arg ns "$RUNNER_NAMESPACE" --arg release "$RUNNER_RELEASE" '{reason:"operator_recovery",deploymentMode:"helm",clusterId:$cluster,runnerNamespace:$ns,releaseName:$release}')"
    instructions="$(api_json POST "/api/projects/$PROJECT_ID/bootstrap-session/runner-deployment-instructions/rotate" "$payload")"
    command="$(jq -r '.bootstrapSecretCommand // ""' <<<"$instructions")"
  fi
  token="$(sed -n 's/.*--from-literal=token="\([^"]*\)".*/\1/p' <<<"$command")"
  config="$(sed -n 's/.*--from-literal=project-config-token="\([^"]*\)".*/\1/p' <<<"$command")"
  [[ -n "$token" && -n "$config" && "$token" != '[masked]' && "$config" != '[masked]' ]] || die "control-plane did not issue usable Runner bootstrap credentials"
  printf '%s\n%s\n' "$token" "$config"
}

install_runner() {
  log "Installing Runner with namespace-scoped Helm release permissions"
  local credentials token config runner_id
  credentials="$(runner_tokens)"
  token="$(sed -n '1p' <<<"$credentials")"
  config="$(sed -n '2p' <<<"$credentials")"
  runner_id="${PROJECT_ID}-runner"
  kubectl --context "$TARGET_PROFILE" create namespace "$RUNNER_NAMESPACE" --dry-run=client -o yaml | kubectl --context "$TARGET_PROFILE" apply -f - >/dev/null
  kubectl --context "$TARGET_PROFILE" create namespace "$FEATURE_NAMESPACE" --dry-run=client -o yaml | kubectl --context "$TARGET_PROFILE" apply -f - >/dev/null
  kubectl --context "$TARGET_PROFILE" -n "$RUNNER_NAMESPACE" create secret generic envpilot-e2e-runner-bootstrap \
    --from-literal=token="$token" --from-literal=project-config-token="$config" --dry-run=client -o yaml | kubectl --context "$TARGET_PROFILE" apply -f - >/dev/null
  helm upgrade --install "$RUNNER_RELEASE" "$RUNNER_CHART" \
    --kube-context "$TARGET_PROFILE" --namespace "$RUNNER_NAMESPACE" \
    --set-string fullnameOverride="$RUNNER_RELEASE" \
    --set-string image.repository=envpilot/runner --set-string image.tag=local --set image.pullPolicy=Never \
    --set-string controlPlane.url="http://host.minikube.internal:18080" \
    --set-string controlPlane.existingSecret=envpilot-e2e-runner-bootstrap \
    --set-string project.id="$PROJECT_ID" --set-string project.clusterId="$CLUSTER_ID" \
    --set-string project.runnerId="$runner_id" --set-string project.namespace="$RUNNER_NAMESPACE" \
    --set-string project.deploymentMode=helm --set-string project.configUrl="http://host.minikube.internal:18080/api/v1/projects/$PROJECT_ID/runner-config" \
    --set-string rbac.featureEnvWriter.mode=preconfiguredNamespaces \
    --set-string "rbac.featureEnvWriter.namespaces[0]=$FEATURE_NAMESPACE" \
    --set controlPlane.authPersistence.createClaim=false >/dev/null
  kubectl --context "$TARGET_PROFILE" -n "$RUNNER_NAMESPACE" rollout restart "deployment/$RUNNER_RELEASE" >/dev/null
  kubectl --context "$TARGET_PROFILE" -n "$RUNNER_NAMESPACE" rollout status "deployment/$RUNNER_RELEASE" --timeout=180s
  wait_for "Runner registration" 90 "[[ \$(api_get /api/projects/$PROJECT_ID/bootstrap-session/runner-status | jq -r .status) == online ]]" >/dev/null
}

start_chart_server() {
  log "Packaging the target-runner-resolvable fixture chart"
  helm package "$CHART_DIR" --destination "$temp_dir" >/dev/null
  local archive
  archive="$(find "$temp_dir" -maxdepth 1 -name 'envpilot-e2e-workload-*.tgz' -print -quit)"
  [[ -n "$archive" ]] || die "failed to package E2E chart"
  CHART_ARCHIVE_NAME="$(basename "$archive")"
  nohup python3 -m http.server "$CHART_PORT" --bind 0.0.0.0 --directory "$temp_dir" >"$temp_dir/chart-server.log" 2>&1 &
  chart_server_pid="$!"
  for _ in $(seq 1 30); do
    if kill -0 "$chart_server_pid" >/dev/null 2>&1 && curl -fsS "http://127.0.0.1:$CHART_PORT/$CHART_ARCHIVE_NAME" -o /dev/null; then
      E2E_CHART_REF="http://host.minikube.internal:$CHART_PORT/$CHART_ARCHIVE_NAME"
      return 0
    fi
    sleep 1
  done
  cat "$temp_dir/chart-server.log" >&2 || true
  die "fixture chart server did not become reachable"
}

complete_bootstrap() {
  local readiness patch scan_start
  readiness="$(api_get "/api/projects/$PROJECT_ID" | jq -r '.deployment_readiness.ready')"
  if [[ "$readiness" == true ]]; then
    log "Fixture project is already deploy-ready"
    return
  fi
  log "Configuring bootstrap through the supported session API"
  patch="$(jq -n \
    --arg base "$BASE_NAMESPACE" --arg ref "$E2E_CHART_REF" \
    '{current_step:10,step_data:{selectedBaseNamespaces:[$base],deployment:{backend:"helm_direct",helmDirect:{chartRef:$ref,namespaceMode:"shared",releaseNamePattern:"envpilot-e2e",namespacePattern:"envpilot-pr-{{ .PRNumber }}",timeout:120,wait:true,createNamespace:false,valuesOverrideStrategy:"merge",imageTagValuePath:"image.tag"}}}}')"
  api_json PATCH "/api/projects/$PROJECT_ID/bootstrap-session" "$patch" >/dev/null
  scan_start="$(api_json POST "/api/projects/$PROJECT_ID/bootstrap-session/resource-scan/start" '{}')"
  if [[ "$(jq -r '.data.resourceScanStatus // empty' <<<"$scan_start")" != "pending" ]]; then
    die "resource scan start was not accepted with selectedBaseNamespaces; response did not report pending status"
  fi
  wait_for "successful resource scan" 180 "[[ \$(api_get /api/projects/$PROJECT_ID/bootstrap-session/agent-status | jq -r .resourceScanStatus) == completed ]]" >/dev/null
  local preflight_status preflight_error
  for attempt in $(seq 1 3); do
    api_json POST "/api/projects/$PROJECT_ID/bootstrap-session/helm-direct/preflight" '{}' >/dev/null
    preflight_status="$(api_get "/api/projects/$PROJECT_ID/bootstrap-session" | jq -r '.data.helmDirectChartValidation.status // empty')"
    if [[ "$preflight_status" == succeeded ]]; then
      break
    fi
    if [[ "$attempt" == 3 ]]; then
      preflight_error="$(api_get "/api/projects/$PROJECT_ID/bootstrap-session" | jq -r '.data.helmDirectChartValidation.error // "chart preflight did not complete"')"
      die "Runner Helm chart preflight failed for $E2E_CHART_REF: $preflight_error"
    fi
    sleep 2
  done
  api_json POST "/api/projects/$PROJECT_ID/bootstrap-session/compile" '{}' >/dev/null
  wait_for "deploy-ready project" 30 "[[ \$(api_get /api/projects/$PROJECT_ID | jq -r .deployment_readiness.ready) == true ]]" >/dev/null
}

assert_deploy_ready() {
  local project readiness missing
  project="$(api_get "/api/projects/$PROJECT_ID")"
  readiness="$(jq -r '.deployment_readiness.ready // false' <<<"$project")"
  if [[ "$readiness" != true ]]; then
    missing="$(jq -r '(.deployment_readiness.missing_prerequisites // []) | join("; ")' <<<"$project")"
    [[ -n "$missing" ]] || missing="readiness was not reported by the API"
    die "fixture project $PROJECT_ID is not deploy-ready: $missing"
  fi
  log "Fixture project is deploy-ready: $PROJECT_ID"
}

create_environment_through_ui() {
  [[ -n "$UI_BASE_URL" ]] || die "set ENVPILOT_E2E_UI_BASE_URL when ENVPILOT_E2E_USE_UI=true"
  log "Creating the environment through the browser UI"
  (
    cd "$WORKSPACE_ROOT/frontend"
    PLAYWRIGHT_SKIP_WEBSERVER=1 \
      PLAYWRIGHT_TEST_DIR=./tests/e2e-real \
      PLAYWRIGHT_BASE_URL="$UI_BASE_URL" \
      ENVPILOT_E2E_API_URL="$API_URL" \
      ENVPILOT_E2E_REAL_CLUSTER=1 \
      ENVPILOT_E2E_RUN_LIFECYCLE=1 \
      ENVPILOT_E2E_KEEP_ENVIRONMENT=1 \
      ENVPILOT_E2E_PROJECT_ID="$PROJECT_ID" \
      ENVPILOT_E2E_ENVIRONMENT_ID="$ENVIRONMENT_ID" \
      npm run test:e2e -- --grep "creates a real full environment through the UI"
  )
}

create_and_verify_environment() {
  log "Creating Full environment through the same public API used by the UI"
  local payload created release namespace control_releases
  if [[ "$USE_UI" == true ]]; then
    create_environment_through_ui
  else
    payload="$(jq -n \
      --arg id "$ENVIRONMENT_ID" --arg project "$PROJECT_ID" --arg provider "$SCM_PROVIDER" --arg repository "$APP_REPOSITORY_URL" --arg prNumber "$PR_NUMBER" \
      '{id:$id,project:$project,product:"generic",mode:"full",ttlHours:1,source:{provider:$provider,repository:$repository,pullRequestId:$prNumber,branch:("feature/envpilot-e2e-" + $prNumber),commit:"",author:"envpilot-e2e"}}')"
    created="$(api_json POST /api/v1/environments "$payload")"
    [[ "$(jq -r .status <<<"$created")" == creating ]] || die "environment was not reserved in creating state"
    wait_for "Runner create result" 120 "[[ \$(api_get /api/v1/environments/$ENVIRONMENT_ID | jq -r .status) == ready ]]" >/dev/null
  fi
  release="$(api_get "/api/v1/environments/$ENVIRONMENT_ID" | jq -er '.helmReleaseName')"
  namespace="$(api_get "/api/v1/environments/$ENVIRONMENT_ID" | jq -er '.targetNamespace')"
  [[ "$namespace" == "$FEATURE_NAMESPACE" ]] || die "environment target namespace $namespace does not match fixture writer namespace $FEATURE_NAMESPACE"
  helm --kube-context "$TARGET_PROFILE" status "$release" --namespace "$namespace" >/dev/null
  control_releases="$(helm --kube-context "$CONTROL_PROFILE" list --all-namespaces -o json | jq -r --arg release "$release" '.[] | select(.name == $release) | .name')"
  [[ -z "$control_releases" ]] || die "Helm release unexpectedly exists in control-plane profile"
  log "Environment is Ready; release $release exists only in $TARGET_PROFILE/$namespace"
}

log "Preparing two-minikube API gateway and local images"
"$DEPLOY_ROOT/scripts/minikube-agent-access.sh" start "$TARGET_PROFILE"
curl --fail --silent --show-error "$API_URL/api/v1/health" >/dev/null
minikube -p "$CONTROL_PROFILE" status >/dev/null
minikube -p "$TARGET_PROFILE" status >/dev/null

kubectl --context "$TARGET_PROFILE" apply -f "$DEPLOY_ROOT/e2e/base-workload.yaml" >/dev/null
kubectl --context "$TARGET_PROFILE" -n "$BASE_NAMESPACE" rollout status deployment/e2e-base-workload --timeout=180s
ensure_project_and_session
validate_scm
install_agent
install_runner
start_chart_server
complete_bootstrap
assert_deploy_ready
create_and_verify_environment

log "E2E passed. The project, healthy base namespace, Agent and Runner remain reusable."
