#!/usr/bin/env bash
# Disposable SM-09 release gate. It intentionally creates every Kubernetes and
# registry resource it needs, never prints registry credentials, and runs
# before the umbrella OCI artifact is published.
set -euo pipefail

: "${ENVPLANE_SM09_CHART:?set the packaged umbrella chart path}"

cluster="${ENVPLANE_SM09_CLUSTER:-envplane-sm09}"
registry="${ENVPLANE_SM09_REGISTRY:-localhost:5001}"
registry_name="${ENVPLANE_SM09_REGISTRY_CONTAINER:-envplane-sm09-registry}"
namespace="${ENVPLANE_SM09_NAMESPACE:-envplane-sm09}"
base_namespace="${ENVPLANE_SM09_BASE_NAMESPACE:-envplane-sm09-base}"
target_namespace="${ENVPLANE_SM09_TARGET_NAMESPACE:-envplane-sm09-target}"
project="${ENVPLANE_SM09_PROJECT:-envplane-e2e-fixture}"
environment="${ENVPLANE_SM09_ENVIRONMENT:-sm09-private-registry}"
release="${ENVPLANE_SM09_RELEASE:-envplane-sm09}"
workload_chart_ref="${ENVPLANE_SM09_WORKLOAD_CHART_REF:-oci://ghcr.io/envplane/envplane-e2e-workload}"
workload_chart_version="${ENVPLANE_SM09_WORKLOAD_CHART_VERSION:-0.1.0}"
fixture_scm_provider="${ENVPLANE_SM09_FIXTURE_SCM_PROVIDER:-github}"
fixture_app_repository_url="${ENVPLANE_SM09_FIXTURE_APP_REPOSITORY_URL:-https://github.com/envplane/envplane-e2e-workload}"
fixture_app_default_branch="${ENVPLANE_SM09_FIXTURE_APP_DEFAULT_BRANCH:-main}"
first_run_browser_gate="${ENVPLANE_SM09_FIRST_RUN_BROWSER_GATE:-0}"
frontend_dir="${ENVPLANE_SM09_FRONTEND_DIR:-}"
tmp="$(mktemp -d)"
pids=()

case "$first_run_browser_gate" in
  0|1) ;;
  *) echo "ENVPLANE_SM09_FIRST_RUN_BROWSER_GATE must be 0 or 1" >&2; exit 2 ;;
esac
if [[ "$first_run_browser_gate" == "1" ]]; then
  [[ -n "$frontend_dir" && -f "$frontend_dir/package.json" ]] || { echo "ENVPLANE_SM09_FRONTEND_DIR must contain the compatible frontend source" >&2; exit 2; }
fi

cleanup() {
  exit_status=$?
  if (( exit_status != 0 )) && kubectl --context "kind-$cluster" cluster-info >/dev/null 2>&1; then
    echo "SM-09 redacted pod diagnostics" >&2
    kubectl --context "kind-$cluster" get pods --all-namespaces -o wide >&2 || true
    echo "SM-09 warning events" >&2
    kubectl --context "kind-$cluster" get events --all-namespaces --field-selector type=Warning >&2 || true
    agent_pod="$(kubectl --context "kind-$cluster" -n "$namespace" get pod -l app.kubernetes.io/name=envplane-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "$agent_pod" ]]; then
      echo "SM-09 Agent preflight diagnostics" >&2
      kubectl --context "kind-$cluster" -n "$namespace" logs "$agent_pod" -c control-plane-preflight --previous 2>/dev/null |
        jq -Rr 'fromjson? | select(.msg == "agent control-plane connectivity check failed") | "message=\(.msg) error=\(.error) retryable=\(.retryable) maxAttempts=\(.maxAttempts)"' >&2 || true
      echo "SM-09 Agent runtime diagnostics" >&2
      kubectl --context "kind-$cluster" -n "$namespace" logs "$agent_pod" -c agent --tail=1000 2>/dev/null |
        jq -Rr 'fromjson? | select(.level == "ERROR" or .level == "WARN") | "level=\(.level) message=\(.msg) error=\(.error // "")"' >&2 || true
    fi
    runner_pod="$(kubectl --context "kind-$cluster" -n "$namespace" get pod -l app.kubernetes.io/name=envplane-runner -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "$runner_pod" ]]; then
      echo "SM-09 Runner runtime diagnostics" >&2
      kubectl --context "kind-$cluster" -n "$namespace" logs "$runner_pod" --tail=100 2>/dev/null |
        jq -Rr 'fromjson? | select(.level == "ERROR" or .level == "WARN") | "level=\(.level) message=\(.msg) error=\(.error // "")"' >&2 || true
    fi
  fi
  for pid in "${pids[@]:-}"; do kill "$pid" >/dev/null 2>&1 || true; done
  kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
  docker rm -f "$registry_name" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

for bin in docker kind kubectl helm curl jq; do command -v "$bin" >/dev/null || { echo "missing $bin" >&2; exit 2; }; done
[[ -f "$ENVPLANE_SM09_CHART" ]] || { echo "packaged umbrella chart is missing" >&2; exit 2; }
if [[ "$first_run_browser_gate" == "1" ]]; then
  command -v go >/dev/null || { echo "missing go required for the ephemeral activation fixture" >&2; exit 2; }
fi

# Credentials are generated only in memory/files with restrictive permissions.
# Neither `set -x` nor an echo of these values is permitted in this harness.
registry_user="envplane"
registry_password="$(openssl rand -hex 24)"
application_secret="$(openssl rand -hex 24)"
umask 077
mkdir -p "$tmp/auth"
docker run --rm --entrypoint htpasswd httpd:2.4 -Bbn "$registry_user" "$registry_password" >"$tmp/auth/htpasswd"
docker run -d --restart=always --name "$registry_name" -v "$tmp/auth:/auth:ro" -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=EnvPlane -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -p 5001:5000 registry:2 >/dev/null

cat >"$tmp/kind.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${registry}"]
    endpoint = ["http://${registry_name}:5000"]
EOF
kind create cluster --name "$cluster" --config "$tmp/kind.yaml"
docker network connect kind "$registry_name" >/dev/null 2>&1 || true
kubectl --context "kind-$cluster" apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "${registry}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

docker pull registry.k8s.io/pause:3.10 >/dev/null
docker tag registry.k8s.io/pause:3.10 "$registry/envplane/sm09:1"
printf '%s' "$registry_password" | docker login "$registry" --username "$registry_user" --password-stdin >/dev/null
docker push "$registry/envplane/sm09:1" >/dev/null
docker logout "$registry" >/dev/null

kubectl --context "kind-$cluster" create namespace "$namespace"

base_values="$(dirname "$0")/../deploy/helm/envplane/values-e2e-local.yaml"
values="$tmp/sm09-values.yaml"
api_token="$(openssl rand -hex 32)"
activation_public_keys_json="[]"
activation_private_key=""
if [[ "$first_run_browser_gate" == "1" ]]; then
  activation_private_key="$tmp/activation-private-key"
  activation_public_keys="$tmp/activation-public-keys.json"
  go run ./cmd/e2e-activation-fixture generate \
    --private-key-output "$activation_private_key" \
    --public-keys-output "$activation_public_keys"
  activation_public_keys_json="$(<"$activation_public_keys")"
fi
cat >"$values" <<EOF
global:
  envplane:
    firstStartRegistration:
      runner:
        namespace: $namespace
    e2eFixture:
      baseNamespace: $base_namespace
      featureNamespace: $target_namespace
envplane-agent:
  controlPlane:
    namespace: $namespace
  watch:
    namespaces: [$base_namespace]
  rbac:
    discovery:
      namespaces: [$base_namespace, $target_namespace]
    materialization:
      enabled: true
      items:
        - id: registry
          sourceNamespace: $base_namespace
          sourceName: registry-source
          targetNamespace: $target_namespace
          targetName: registry-pull
        - id: application
          sourceNamespace: $base_namespace
          sourceName: application-source
          targetNamespace: $target_namespace
          targetName: application-config
envplane-control-plane:
  env:
    ENVPLANE_ENABLE_RELEASE_TEST_CONTROLS: "1"
    ENVPLANE_API_WRITE_TOKEN: $api_token
  commercialization:
    license:
      activationPublicKeysJSON: '$activation_public_keys_json'
      graceDays: 0
envplane-runner:
  controlPlane:
    namespace: $namespace
  project:
    configUrl: http://envplane-control-plane.$namespace.svc:8080/api/v1/projects/$project/runner-config
  rbac:
    featureEnvWriter:
      namespaces: [$target_namespace]
EOF
helm upgrade --install "$release" "$ENVPLANE_SM09_CHART" --kube-context "kind-$cluster" --namespace "$namespace" --create-namespace --values "$base_values" --values "$values" --wait --timeout 15m
if kubectl --context "kind-$cluster" -n "$namespace" get secret release-registry-pull >/dev/null 2>&1; then
  echo "SM-09 must not create a runtime GHCR pull Secret" >&2
  exit 1
fi
if ! kubectl --context "kind-$cluster" -n "$namespace" get deployments -l "app.kubernetes.io/instance=$release" -o json |
  jq -e '[.items[] | (.spec.template.spec.imagePullSecrets // []) | length] | all(. == 0)' >/dev/null; then
  echo "SM-09 runtime Deployments must pull public artifacts without imagePullSecrets" >&2
  exit 1
fi
kubectl --context "kind-$cluster" -n "$base_namespace" create secret docker-registry registry-source --docker-server="$registry" --docker-username="$registry_user" --docker-password="$registry_password" >/dev/null
kubectl --context "kind-$cluster" -n "$base_namespace" create secret generic application-source --from-literal=config="$application_secret" >/dev/null
kubectl --context "kind-$cluster" -n "$namespace" rollout status deployment/envplane-control-plane --timeout=5m
kubectl --context "kind-$cluster" -n "$namespace" rollout status deployment/envplane-agent --timeout=5m

api_port=18080
kubectl --context "kind-$cluster" -n "$namespace" port-forward svc/envplane-control-plane "$api_port:8080" >"$tmp/port-forward.log" 2>&1 &
api_port_forward_pid=$!
pids+=("$api_port_forward_pid")
api="http://127.0.0.1:$api_port"
frontend_port=13000
tenant_id="${ENVPLANE_SM09_TENANT_ID:-default}"
if [[ "$first_run_browser_gate" == "1" ]]; then
  kubectl --context "kind-$cluster" -n "$namespace" rollout status deployment/envplane-frontend --timeout=5m
  kubectl --context "kind-$cluster" -n "$namespace" port-forward svc/envplane-frontend "$frontend_port:3000" >"$tmp/frontend-port-forward.log" 2>&1 &
  frontend_port_forward_pid=$!
  pids+=("$frontend_port_forward_pid")
fi

wait_for_port_forward() {
  local pid="$1" label="$2" log_file="$3" url="$4" attempt
  for attempt in $(seq 1 90); do
    if curl --noproxy '*' --silent --show-error --fail \
      -H "Authorization: Bearer $api_token" -H "x-envplane-tenant: $tenant_id" \
      "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "SM-09 $label port-forward exited before becoming reachable" >&2
      tail -40 "$log_file" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "SM-09 $label port-forward did not become reachable within 90 seconds" >&2
  tail -40 "$log_file" >&2 || true
  return 1
}

wait_for_port_forward "$api_port_forward_pid" "control-plane API" "$tmp/port-forward.log" "$api/api/v1/health"
if [[ "$first_run_browser_gate" == "1" ]]; then
  wait_for_port_forward "$frontend_port_forward_pid" "frontend" "$tmp/frontend-port-forward.log" "http://127.0.0.1:$frontend_port/"
fi

api_curl() {
  local output response_meta status_code curl_status request_url
  output="$(mktemp "$tmp/api-response.XXXXXX")"
  request_url=""
  for argument in "$@"; do
    if [[ "$argument" == http://* || "$argument" == https://* ]]; then
      request_url="$argument"
      break
    fi
  done
  set +e
  response_meta="$(curl --noproxy '*' --silent --show-error -o "$output" -w '%{http_code}' -H "Authorization: Bearer $api_token" -H "x-envplane-tenant: $tenant_id" "$@")"
  curl_status=$?
  set -e
  status_code="${response_meta:-000}"
  if (( curl_status != 0 )) || [[ ! "$status_code" =~ ^2[0-9]{2}$ ]]; then
    if jq -e 'type == "object"' "$output" >/dev/null 2>&1; then
      jq -c --arg endpoint "${request_url#"$api"}" --arg status "$status_code" \
        '{endpoint: $endpoint, status: $status, code: (.code // ""), field: (.field // ""), error: (.error // "")}' "$output" >&2
    else
      jq -cn --arg endpoint "${request_url#"$api"}" --arg status "$status_code" \
        '{endpoint: $endpoint, status: $status, code: "non_json_http_response"}' >&2
    fi
    rm -f "$output"
    if (( curl_status != 0 )); then
      return "$curl_status"
    fi
    return 1
  fi
  cat "$output"
  rm -f "$output"
}
api_call() {
  local output="$1" label="$2" response_headers="$1.headers" response_meta status_code content_type body_bytes allow_methods curl_status
  shift 2
  set +e
  response_meta="$(curl --noproxy '*' --silent --show-error -D "$response_headers" -o "$output" -w $'%{http_code}\t%{content_type}' -H "Authorization: Bearer $api_token" -H "x-envplane-tenant: $tenant_id" "$@")"
  curl_status=$?
  set -e
  status_code="${response_meta%%$'\t'*}"
  content_type="${response_meta#*$'\t'}"
  if (( curl_status == 0 )) && [[ "$status_code" =~ ^2[0-9]{2}$ ]]; then
    return 0
  fi
  if jq -e 'type == "object"' "$output" >/dev/null 2>&1; then
    jq -c --arg status "$status_code" '{status: $status, code: (.code // ""), field: (.field // ""), error: (.error // "")}' "$output" >&2
  else
    body_bytes="$(wc -c <"$output" | tr -d '[:space:]')"
    allow_methods="$(awk 'BEGIN {IGNORECASE=1} /^allow:/ {sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit}' "$response_headers")"
    jq -cn --arg status "$status_code" --arg contentType "$content_type" --arg allow "$allow_methods" --argjson bodyBytes "$body_bytes" \
      '{status: $status, code: "non_json_http_response", contentType: $contentType, bodyBytes: $bodyBytes, allow: $allow}' >&2
  fi
  echo "SM-09 API request failed: $label (curl=$curl_status http=${status_code:-000})" >&2
  return 1
}
api_curl "$api/api/v1/health" >/dev/null
fixture_project_patch="$(jq -cn \
  --arg provider "$fixture_scm_provider" \
  --arg repository "$fixture_app_repository_url" \
  --arg branch "$fixture_app_default_branch" \
  '{git_repo: {provider: $provider, url: $repository, default_branch: $branch}}')"
api_call "$tmp/project.json" "set fixture project SCM metadata" -X PATCH "$api/api/v1/projects/$project" -H 'content-type: application/json' -d "$fixture_project_patch"
jq -e --arg provider "$fixture_scm_provider" --arg repository "$fixture_app_repository_url" \
  '.git_repo.provider == $provider and .git_repo.url == $repository' "$tmp/project.json" >/dev/null || {
  echo "SM-09 fixture project SCM metadata was not persisted" >&2
  exit 1
}

for _ in $(seq 1 120); do
  agent_status="$(api_curl "$api/api/v1/projects/$project/bootstrap-session/agent-status")"
  jq -e '(.status == "connected" or .status == "online")' <<<"$agent_status" >/dev/null 2>&1 && break
  sleep 2
done
if ! jq -e '(.status == "connected" or .status == "online")' <<<"$agent_status" >/dev/null; then
  jq -c '{status: (.status // ""), effectiveStatus: (.effectiveStatus // ""), error: (.error // ""), lastSeenAt: (.lastSeenAt // "")}' <<<"$agent_status" >&2
  echo "SM-09 Agent did not report a usable status" >&2
	exit 1
fi

api_call "$tmp/resource-scan.json" "start Agent resource scan" -X POST "$api/api/v1/projects/$project/bootstrap-session/resource-scan/start"
for _ in $(seq 1 120); do
  agent_status="$(api_curl "$api/api/v1/projects/$project/bootstrap-session/agent-status")"
  jq -e '.resourceScanStatus == "completed"' <<<"$agent_status" >/dev/null 2>&1 && break
  sleep 2
done
if ! jq -e '.resourceScanStatus == "completed"' <<<"$agent_status" >/dev/null; then
  jq -c '{status: (.status // ""), resourceScanStatus: (.resourceScanStatus // ""), resourceScanError: (.resourceScanError // ""), resourceScanDeadlineAt: (.resourceScanDeadlineAt // "")}' <<<"$agent_status" >&2
  echo "SM-09 Agent resource scan did not complete" >&2
  exit 1
fi

# Drive the public Bootstrap API. The payload contains references and bounded
# metadata only; it never contains a Secret value or registry credential.
api_call "$tmp/bootstrap.json" "save deployment, secret strategies, and final review" -X PATCH "$api/api/v1/projects/$project/bootstrap-session" -H 'content-type: application/json' -d "{\"current_step\":10,\"stepData\":{\"deployment\":{\"backend\":\"helm_direct\",\"helmDirect\":{\"chartRef\":\"$workload_chart_ref\",\"chartVersion\":\"$workload_chart_version\",\"namespaceMode\":\"shared\",\"namespacePattern\":\"$target_namespace\",\"releaseNamePattern\":\"{{ .project.id }}-{{ .environment.name }}\",\"timeout\":180,\"wait\":true,\"createNamespace\":false,\"valuesOverrideStrategy\":\"merge\",\"imageTagValuePath\":\"image.tag\"}},\"secretStrategies\":{\"registry\":{\"strategy\":\"encrypted clone\",\"required\":true,\"serviceId\":\"service/private-image\",\"namespace\":\"$base_namespace\",\"secretName\":\"registry-source\",\"targetName\":\"registry-pull\",\"retentionHours\":24},\"application\":{\"strategy\":\"encrypted clone\",\"required\":true,\"serviceId\":\"service/private-image\",\"namespace\":\"$base_namespace\",\"secretName\":\"application-source\",\"targetName\":\"application-config\",\"retentionHours\":24}}}}"
api_call "$tmp/chart-preflight.json" "start Runner Helm chart preflight" -X POST "$api/api/v1/projects/$project/bootstrap-session/helm-direct/preflight"
for _ in $(seq 1 120); do
  bootstrap_session="$(api_curl "$api/api/v1/projects/$project/bootstrap-session")"
  jq -e --arg chartRef "$workload_chart_ref" --arg chartVersion "$workload_chart_version" \
    '.data.helmDirectChartValidation | .status == "succeeded" and .chartRef == $chartRef and .chartVersion == $chartVersion' \
    <<<"$bootstrap_session" >/dev/null 2>&1 && break
  sleep 2
done
if ! jq -e --arg chartRef "$workload_chart_ref" --arg chartVersion "$workload_chart_version" \
  '.data.helmDirectChartValidation | .status == "succeeded" and .chartRef == $chartRef and .chartVersion == $chartVersion' \
  <<<"$bootstrap_session" >/dev/null; then
  jq -c '{status: (.status // ""), chartValidation: (.data.helmDirectChartValidation // {} | {status: (.status // ""), errorCode: (.errorCode // ""), error: (.error // "")})}' <<<"$bootstrap_session" >&2
  echo "SM-09 Runner Helm chart preflight did not complete" >&2
  exit 1
fi
api_call "$tmp/compiled.json" "compile Bootstrap session" -X POST "$api/api/v1/projects/$project/bootstrap-session/compile"
api_call "$tmp/environment.json" "create environment" -X POST "$api/api/v1/environments" -H 'content-type: application/json' -d "{\"id\":\"$environment\",\"project\":\"$project\",\"clusterId\":\"local-e2e\",\"namespace\":\"$target_namespace\",\"mode\":\"full\"}"
materialization_status="$(api_curl "$api/api/v1/environments/$environment/secret-materialization")"
plan_id="$(jq -er '.planId' <<<"$materialization_status")"

assert_rejected_fault() {
  local fault="$1" output="$tmp/fault-$1.json" status_code
  status_code="$(curl --noproxy '*' -sS -o "$output" -w '%{http_code}' -H "Authorization: Bearer $api_token" -H "x-envplane-tenant: $tenant_id" -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"materialize\",\"testFault\":\"$fault\"}")"
  [[ "$status_code" == "409" ]]
  jq -e '.error | type == "string"' "$output" >/dev/null
}

assert_rejected_fault wrong_tenant
assert_rejected_fault namespace_escape
assert_rejected_fault expired_lease
assert_rejected_fault tampered_envelope

if [[ "$first_run_browser_gate" == "1" ]]; then
  for _ in $(seq 1 60); do
    setup_token="$(kubectl --context "kind-$cluster" -n "$namespace" get secret -l envplane.io/managed-secret=authentication -o jsonpath='{.items[0].data.setup-token}' 2>/dev/null | base64 --decode 2>/dev/null || true)"
    [[ -n "$setup_token" ]] && break
    sleep 1
  done
  [[ -n "${setup_token:-}" ]] || { echo "clean-install setup credential was not created" >&2; exit 1; }
  activation_identity="$(api_curl "$api/api/v1/license/activation/identity")"
  installation_id="$(jq -er '.installationId' <<<"$activation_identity")"
  activation_tenant_id="$(jq -er '.tenantId' <<<"$activation_identity")"
  activation_code_file="$tmp/first-run-activation-code"
  go run ./cmd/e2e-activation-fixture sign \
    --private-key "$activation_private_key" \
    --output "$activation_code_file" \
    --installation-id "$installation_id" \
    --tenant-id "$activation_tenant_id" \
    --expires-in 45s
  activation_code="$(<"$activation_code_file")"
  (
    cd "$frontend_dir"
    ENVPLANE_DISABLE_WEB_SERVER=1 \
    ENVPLANE_E2E_REAL_CLUSTER=1 \
    ENVPLANE_E2E_FIRST_RUN=1 \
    ENVPLANE_E2E_FIRST_RUN_SETUP_TOKEN="$setup_token" \
    ENVPLANE_E2E_FIRST_RUN_ACTIVATION_CODE="$activation_code" \
    ENVPLANE_E2E_FIRST_RUN_EXPECT_EXPIRED=1 \
    ENVPLANE_E2E_RUN_LIFECYCLE=1 \
    ENVPLANE_E2E_PROJECT_ID="$project" \
    ENVPLANE_E2E_ENVIRONMENT_ID="${environment}-browser" \
    ENVPLANE_E2E_BASE_URL="http://127.0.0.1:$frontend_port" \
    ENVPLANE_E2E_API_URL="$api" \
    npm run test:e2e:real -- --grep "creates a real full environment through the UI"
  )
  kubectl --context "kind-$cluster" -n "$target_namespace" delete secret registry-pull application-config --ignore-not-found >/dev/null
fi

# A private image must fail before its pull credential exists.
kubectl --context "kind-$cluster" -n "$target_namespace" run before-materialization --image="$registry/envplane/sm09:1" --restart=Never >/dev/null
sleep 8
! kubectl --context "kind-$cluster" -n "$target_namespace" get pod before-materialization -o jsonpath='{.status.phase}' | grep -qx Running

# A foreign Secret at an approved target name must never be adopted. This is
# metadata-only and is deleted before the retry below.
kubectl --context "kind-$cluster" -n "$target_namespace" create secret generic registry-pull --from-literal=owner=foreign >/dev/null
api_curl -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"materialize\"}" >"$tmp/foreign-dispatch.json"
for _ in $(seq 1 120); do
  status="$(api_curl "$api/api/v1/projects/$project/secret-materialization?planId=$plan_id")"
  jq -e '.state == "failed" and (.items[] | select(.id == "registry") | .errorCode == "conflict")' <<<"$status" >/dev/null 2>&1 && break
  sleep 2
done
if ! jq -e '.state == "failed" and (.items[] | select(.id == "registry") | .errorCode == "conflict")' <<<"$status" >/dev/null; then
  jq -c '{state: (.state // ""), items: [.items[]? | {id: (.id // ""), state: (.state // ""), errorCode: (.errorCode // "")} ]}' <<<"$status" >&2
  echo "SM-09 foreign target conflict was not reported" >&2
  exit 1
fi
kubectl --context "kind-$cluster" -n "$target_namespace" delete secret registry-pull >/dev/null

api_curl -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"materialize\"}" >"$tmp/dispatch.json"
for _ in $(seq 1 120); do
  status="$(api_curl "$api/api/v1/projects/$project/secret-materialization?planId=$plan_id")"
  jq -e '.state == "ready" and (.items | all(.[]; .state == "ready"))' <<<"$status" >/dev/null 2>&1 && break
  sleep 2
done
if ! jq -e '.state == "ready" and (.items | all(.[]; .state == "ready"))' <<<"$status" >/dev/null; then
  jq -c '{state: (.state // ""), items: [.items[]? | {id: (.id // ""), state: (.state // ""), errorCode: (.errorCode // "")} ]}' <<<"$status" >&2
  echo "SM-09 materialization did not reach ready" >&2
  exit 1
fi
# Keep this selector bound to the releaseNamePattern submitted to Bootstrap
# above (`{{ .project.id }}-{{ .environment.name }}`). The runtime status can
# already be Ready while an incorrectly guessed label would make this gate
# report no workload at all.
environment_release="$project-$environment"
for _ in $(seq 1 180); do
  environment_status="$(api_curl "$api/api/v1/environments/$environment")"
  jq -e '(.status == "ready" or .status == "running") and (.url | type == "string" and length > 0)' <<<"$environment_status" >/dev/null 2>&1 && break
  sleep 2
done
if ! jq -e '(.status == "ready" or .status == "running") and (.url | type == "string" and length > 0)' <<<"$environment_status" >/dev/null; then
  jq -c '{status: (.status // ""), url: (.url // ""), error: (.error // "")}' <<<"$environment_status" >&2
  echo "SM-11 clean-install environment did not reach Ready with a URL" >&2
  exit 1
fi
kubectl --context "kind-$cluster" -n "$target_namespace" rollout status deployment -l "app.kubernetes.io/instance=$environment_release" --timeout=5m
kubectl --context "kind-$cluster" -n "$target_namespace" get pods -l "app.kubernetes.io/instance=$environment_release" -o json |
  jq -e '.items | length > 0 and all(.[]; .status.phase == "Running")' >/dev/null
echo "SM-11 clean-install environment ready: $(jq -r '.url' <<<"$environment_status")"

if [[ "$first_run_browser_gate" == "1" ]]; then
  (
    cd "$frontend_dir"
    ENVPLANE_DISABLE_WEB_SERVER=1 \
    ENVPLANE_E2E_REAL_CLUSTER=1 \
    ENVPLANE_E2E_FIRST_RUN=1 \
    ENVPLANE_E2E_FIRST_RUN_SETUP_TOKEN="$setup_token" \
    ENVPLANE_E2E_FIRST_RUN_ACTIVATION_CODE="$activation_code" \
    ENVPLANE_E2E_FIRST_RUN_EXPECT_EXPIRED=1 \
    ENVPLANE_E2E_FIRST_RUN_ASSERT_FAIL_CLOSED=1 \
    ENVPLANE_E2E_PROJECT_ID="$project" \
    ENVPLANE_E2E_ENVIRONMENT_ID="$environment" \
    ENVPLANE_E2E_BASE_URL="http://127.0.0.1:$frontend_port" \
    ENVPLANE_E2E_API_URL="$api" \
    npm run test:e2e:real -- --grep "claims, resumes, verifies lifecycle evidence"
  )
fi

! grep -Fq "$registry_password" "$tmp"/*.json "$tmp"/*.log 2>/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" get secret registry-pull >/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" get secret application-config >/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" run after-materialization --image="$registry/envplane/sm09:1" --restart=Never --overrides='{"spec":{"imagePullSecrets":[{"name":"registry-pull"}]}}' >/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" wait --for=condition=Ready pod/after-materialization --timeout=120s

# Explicit source rotation is a fresh materialization command, never a silent
# mutation. Restarting Agent validates lease/queue recovery before the command.
kubectl --context "kind-$cluster" -n "$namespace" rollout restart deployment/envplane-agent
kubectl --context "kind-$cluster" -n "$namespace" rollout status deployment/envplane-agent --timeout=5m
before_rotation="$(kubectl --context "kind-$cluster" -n "$target_namespace" get secret application-config -o jsonpath='{.metadata.resourceVersion}')"
rotated_application_secret="$(openssl rand -hex 24)"
kubectl --context "kind-$cluster" -n "$base_namespace" delete secret application-source >/dev/null
kubectl --context "kind-$cluster" -n "$base_namespace" create secret generic application-source --from-literal=config="$rotated_application_secret" >/dev/null
api_curl -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"materialize\"}" >"$tmp/rotation.json"
for _ in $(seq 1 120); do
  after_rotation="$(kubectl --context "kind-$cluster" -n "$target_namespace" get secret application-config -o jsonpath='{.metadata.resourceVersion}')"
  [[ "$after_rotation" != "$before_rotation" ]] && break
  sleep 2
done
[[ "$after_rotation" != "$before_rotation" ]]
api_curl -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"cleanup\"}" >"$tmp/cleanup.json"
for _ in $(seq 1 120); do kubectl --context "kind-$cluster" -n "$target_namespace" get secret registry-pull >/dev/null 2>&1 || break; sleep 2; done
! kubectl --context "kind-$cluster" -n "$target_namespace" get secret registry-pull >/dev/null 2>&1
! kubectl --context "kind-$cluster" -n "$target_namespace" get secret application-config >/dev/null 2>&1
echo "SM-09 private-registry lifecycle gate passed"
