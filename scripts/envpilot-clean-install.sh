#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="${ROOT_DIR}/deploy/helm"

NAMESPACE="${ENVPILOT_NAMESPACE:-envpilot}"
PROJECT_ID="${ENVPILOT_PROJECT_ID:-default}"
CLUSTER_ID="${ENVPILOT_CLUSTER_ID:?set ENVPILOT_CLUSTER_ID}"
AGENT_ID="${ENVPILOT_AGENT_ID:-envpilot-agent}"
RUNNER_ID="${ENVPILOT_RUNNER_ID:-${PROJECT_ID}-runner}"
RUNNER_NAMESPACE="${ENVPILOT_RUNNER_NAMESPACE:-${NAMESPACE}}"
RUNNER_RELEASE_NAME="${ENVPILOT_RUNNER_RELEASE_NAME:-envpilot-runner-$(date +%s)}"
DEPLOYMENT_MODE="${ENVPILOT_RUNNER_DEPLOYMENT_MODE:-helm}"

CONTROL_PLANE_RELEASE="${ENVPILOT_CONTROL_PLANE_RELEASE:-envpilot}"
AGENT_RELEASE="${ENVPILOT_AGENT_RELEASE:-envpilot-agent}"
RUNNER_RELEASE="${ENVPILOT_RUNNER_RELEASE:-envpilot-runner}"

# The shell installer is primarily used for local minikube installs. A
# ClusterIP frontend is not reachable from the host and an ALB ingress is not
# provisioned by minikube, so use a minikube service tunnel there. Clusters
# without a running minikube profile retain the production ingress default.
MINIKUBE_PROFILE="${ENVPILOT_MINIKUBE_PROFILE:-${MINIKUBE_PROFILE:-}}"
if [[ -z "${MINIKUBE_PROFILE}" ]] && command -v kubectl >/dev/null 2>&1; then
  MINIKUBE_PROFILE="$(kubectl config current-context 2>/dev/null || true)"
fi
if [[ -n "${ENVPILOT_FRONTEND_ACCESS_MODE:-}" ]]; then
  FRONTEND_ACCESS_MODE="${ENVPILOT_FRONTEND_ACCESS_MODE}"
elif command -v minikube >/dev/null 2>&1 && [[ -n "${MINIKUBE_PROFILE}" ]] && minikube status -p "${MINIKUBE_PROFILE}" >/dev/null 2>&1; then
  FRONTEND_ACCESS_MODE="nodeport"
else
  FRONTEND_ACCESS_MODE="ingress"
fi
FRONTEND_NODE_PORT="${ENVPILOT_FRONTEND_NODE_PORT:-}"
FRONTEND_SERVICE="${CONTROL_PLANE_RELEASE}-control-plane-frontend"
FRONTEND_ACCESS_PID_FILE="${ENVPILOT_FRONTEND_ACCESS_PID_FILE:-/tmp/envpilot-frontend-service.pid}"
FRONTEND_ACCESS_LOG="${ENVPILOT_FRONTEND_ACCESS_LOG:-/tmp/envpilot-frontend-service.log}"

GHCR_SECRET="${ENVPILOT_GHCR_SECRET:-ghcr-envpilot}"
GHCR_SERVER="${ENVPILOT_GHCR_SERVER:-ghcr.io}"
GHCR_USERNAME="${ENVPILOT_GHCR_USERNAME:-envpilot}"
GHCR_TOKEN="${ENVPILOT_GHCR_TOKEN:-}"

API_IMAGE="${ENVPILOT_API_IMAGE:-ghcr.io/envpilot/api}"
FRONTEND_IMAGE="${ENVPILOT_FRONTEND_IMAGE:-ghcr.io/envpilot/frontend}"
AGENT_IMAGE="${ENVPILOT_AGENT_IMAGE:-ghcr.io/envpilot/agent}"
RUNNER_IMAGE="${ENVPILOT_RUNNER_IMAGE:-ghcr.io/envpilot/runner}"
RELEASE_VERSION="${ENVPILOT_RELEASE_VERSION:-0.1.14}"
IMAGE_TAG="${ENVPILOT_IMAGE_TAG:-}"
API_IMAGE_TAG="${ENVPILOT_API_IMAGE_TAG:-0.1.5}"
FRONTEND_IMAGE_TAG="${ENVPILOT_FRONTEND_IMAGE_TAG:-0.1.5}"
AGENT_IMAGE_TAG="${ENVPILOT_AGENT_IMAGE_TAG:-0.1.4}"
RUNNER_IMAGE_TAG="${ENVPILOT_RUNNER_IMAGE_TAG:-0.1.4}"
IMAGE_PULL_POLICY="${ENVPILOT_IMAGE_PULL_POLICY:-Always}"

STORAGE_CLASS="${ENVPILOT_STORAGE_CLASS:-}"
NODE_ARCH="${ENVPILOT_NODE_ARCH:-}"
TOLERATION_KEY="${ENVPILOT_TOLERATION_KEY:-}"
TOLERATION_VALUE="${ENVPILOT_TOLERATION_VALUE:-}"
TOLERATION_EFFECT="${ENVPILOT_TOLERATION_EFFECT:-NoSchedule}"

MODE="${1:-install}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

helm_set_args=()
add_set() {
  helm_set_args+=(--set "$1=$2")
}

add_common_scheduling_values() {
  local prefix="$1"
  if [[ -n "${NODE_ARCH}" ]]; then
    add_set "${prefix}nodeSelector.kubernetes\\.io/arch" "${NODE_ARCH}"
  fi
  if [[ -n "${TOLERATION_KEY}" ]]; then
    add_set "${prefix}tolerations[0].key" "${TOLERATION_KEY}"
    add_set "${prefix}tolerations[0].operator" "Equal"
    add_set "${prefix}tolerations[0].value" "${TOLERATION_VALUE}"
    add_set "${prefix}tolerations[0].effect" "${TOLERATION_EFFECT}"
  fi
}

clean_namespace() {
  helm uninstall "${RUNNER_RELEASE}" -n "${NAMESPACE}" --ignore-not-found || true
  helm uninstall "${AGENT_RELEASE}" -n "${NAMESPACE}" --ignore-not-found || true
  helm uninstall "${CONTROL_PLANE_RELEASE}" -n "${NAMESPACE}" --ignore-not-found || true
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found --wait=true
  kubectl delete clusterrole "${AGENT_RELEASE}-envpilot-agent" "${AGENT_RELEASE}-envpilot-agent-chart" "${RUNNER_RELEASE}-envpilot-runner-chart-discovery-reader" --ignore-not-found || true
  kubectl delete clusterrolebinding "${AGENT_RELEASE}-envpilot-agent" "${AGENT_RELEASE}-envpilot-agent-chart" "${RUNNER_RELEASE}-envpilot-runner-chart-discovery-reader" --ignore-not-found || true
}

create_namespace_and_pull_secret() {
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  if [[ -z "${GHCR_TOKEN}" ]]; then
    if command -v gh >/dev/null 2>&1; then
      GHCR_TOKEN="$(gh auth token --hostname github.com)"
    else
      echo "set ENVPILOT_GHCR_TOKEN or install gh" >&2
      exit 1
    fi
  fi
  kubectl create secret docker-registry "${GHCR_SECRET}" \
    --namespace "${NAMESPACE}" \
    --docker-server="${GHCR_SERVER}" \
    --docker-username="${GHCR_USERNAME}" \
    --docker-password="${GHCR_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

install_control_plane() {
  helm_set_args=()
  add_set "image.repository" "${API_IMAGE}"
  add_set "image.tag" "${IMAGE_TAG:-${API_IMAGE_TAG}}"
  add_set "image.pullPolicy" "${IMAGE_PULL_POLICY}"
  add_set "frontend.image.repository" "${FRONTEND_IMAGE}"
  add_set "frontend.image.tag" "${IMAGE_TAG:-${FRONTEND_IMAGE_TAG}}"
  add_set "frontend.image.pullPolicy" "${IMAGE_PULL_POLICY}"
  add_set "imagePullSecrets[0].name" "${GHCR_SECRET}"
  add_set "dependencyWait.enabled" "true"
  add_set "env.ENVPILOT_DEPENDENCY_WAIT_TIMEOUT_SECONDS" "120"
  add_set "env.ENVPILOT_DEPENDENCY_WAIT_INTERVAL_SECONDS" "2"
  add_set "env.ENVPILOT_API_CONTRACT_VERSION" "1"
  case "${FRONTEND_ACCESS_MODE}" in
    nodeport)
      add_set "ingress.enabled" "false"
      add_set "frontend.service.type" "NodePort"
      if [[ -n "${FRONTEND_NODE_PORT}" ]]; then
        add_set "frontend.service.nodePort" "${FRONTEND_NODE_PORT}"
      fi
      ;;
    ingress)
      add_set "frontend.service.type" "ClusterIP"
      ;;
    *)
      echo "unsupported ENVPILOT_FRONTEND_ACCESS_MODE=${FRONTEND_ACCESS_MODE}; use nodeport or ingress" >&2
      exit 1
      ;;
  esac
  if [[ -n "${STORAGE_CLASS}" ]]; then
    add_set "postgres.persistence.storageClassName" "${STORAGE_CLASS}"
    add_set "redis.persistence.storageClassName" "${STORAGE_CLASS}"
  fi
  add_common_scheduling_values ""
  add_common_scheduling_values "frontend."
  helm upgrade --install "${CONTROL_PLANE_RELEASE}" "${CHART_DIR}/envpilot-control-plane" \
    --namespace "${NAMESPACE}" \
    "${helm_set_args[@]}"
  kubectl rollout status "deployment/envpilot-control-plane" -n "${NAMESPACE}" --timeout=240s
  kubectl rollout status "deployment/envpilot-control-plane-frontend" -n "${NAMESPACE}" --timeout=240s
}

api_url() {
  echo "http://127.0.0.1:${ENVPILOT_LOCAL_PORT:-18080}"
}

start_port_forward() {
  local port="${ENVPILOT_LOCAL_PORT:-18080}"
  kubectl port-forward -n "${NAMESPACE}" svc/envpilot-control-plane "${port}:8080" >/tmp/envpilot-port-forward.log 2>&1 &
  PORT_FORWARD_PID="$!"
  trap 'kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true' EXIT
  for _ in $(seq 1 60); do
    if curl -fsS "$(api_url)/api/v1/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  cat /tmp/envpilot-port-forward.log >&2 || true
  echo "control-plane API did not become reachable through port-forward" >&2
  exit 1
}

verify_api_capabilities() {
  local capabilities
  capabilities="$(curl -fsS "$(api_url)/api/v1/capabilities")" || {
    echo "control-plane capability endpoint is unavailable; refusing to continue with an unverified API image" >&2
    exit 1
  }
  if [[ "$(jq -r '.apiContractVersion // empty' <<<"${capabilities}")" != "1" ]] || [[ "$(jq -r '.features.scmOfflineBootstrap // false' <<<"${capabilities}")" != "true" ]]; then
    echo "control-plane API capability contract mismatch: expected apiContractVersion=1 and scmOfflineBootstrap=true; got ${capabilities}" >&2
    exit 1
  fi
}

create_bootstrap_secrets() {
  local agent_token
  agent_token="$(curl -fsS -X POST "$(api_url)/api/projects/${PROJECT_ID}/bootstrap-session/agent-token" \
    -H 'Content-Type: application/json' \
    -d "{\"clusterId\":\"${CLUSTER_ID}\",\"agentId\":\"${AGENT_ID}\"}" | jq -r '.registrationToken')"
  kubectl create secret generic envpilot-agent-bootstrap \
    --namespace "${NAMESPACE}" \
    --from-literal=registration-token="${agent_token}" \
    --dry-run=client -o yaml | kubectl apply -f -

  local cmd registration_token project_config_token
  cmd="$(curl -fsS -X POST "$(api_url)/api/projects/${PROJECT_ID}/bootstrap-session/runner-deployment-instructions" \
    -H 'Content-Type: application/json' \
    -d "{\"deploymentMode\":\"${DEPLOYMENT_MODE}\",\"clusterId\":\"${CLUSTER_ID}\",\"runnerNamespace\":\"${RUNNER_NAMESPACE}\",\"releaseName\":\"${RUNNER_RELEASE_NAME}\"}" | jq -r '.bootstrapSecretCommand')"
  registration_token="$(printf '%s' "${cmd}" | sed -n 's/.*--from-literal=token="\([^"]*\)".*/\1/p')"
  project_config_token="$(printf '%s' "${cmd}" | sed -n 's/.*--from-literal=project-config-token="\([^"]*\)".*/\1/p')"
  if [[ "${registration_token}" == "[masked]" || "${project_config_token}" == "[masked]" ]]; then
    echo "runner bootstrap credentials are masked by control-plane; refusing to create or update envpilot-runner-bootstrap" >&2
    echo "rotate the credentials explicitly in the Bootstrap wizard (or POST $(api_url)/api/projects/${PROJECT_ID}/bootstrap-session/runner-deployment-instructions/rotate with the same runner identity and a reason such as wrong_cluster), then rerun this installer" >&2
    exit 2
  fi
  if [[ -z "${registration_token}" || -z "${project_config_token}" ]]; then
    echo "failed to extract runner bootstrap tokens from control-plane response" >&2
    exit 1
  fi
  kubectl create secret generic envpilot-runner-bootstrap \
    --namespace "${NAMESPACE}" \
    --from-literal=token="${registration_token}" \
    --from-literal=project-config-token="${project_config_token}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

install_agent() {
  helm_set_args=()
  add_set "image.repository" "${AGENT_IMAGE}"
  add_set "image.tag" "${AGENT_IMAGE_TAG}"
  add_set "image.pullPolicy" "${IMAGE_PULL_POLICY}"
  add_set "imagePullSecrets[0].name" "${GHCR_SECRET}"
  add_set "controlPlane.url" "http://envpilot-control-plane.${NAMESPACE}.svc.cluster.local:8080"
  add_set "controlPlane.existingSecret" "envpilot-agent-bootstrap"
  add_set "cluster.id" "${CLUSTER_ID}"
  add_set "bootstrap.projectId" "${PROJECT_ID}"
  add_set "agent.id" "${AGENT_ID}"
  add_set "dependencyWait.enabled" "true"
  add_set "dependencyWait.healthPath" "/api/v1/health"
  add_set "agent.authPersistence.createClaim" "true"
  if [[ -n "${STORAGE_CLASS}" ]]; then
    add_set "agent.authPersistence.storageClassName" "${STORAGE_CLASS}"
  fi
  add_set "agent.authPersistence.size" "1Mi"
  add_set "agent.authPersistence.accessModes[0]" "ReadWriteOnce"
  add_set "installValidation.enabled" "false"
  add_set "ttlCleanup.enabled" "false"
  add_common_scheduling_values ""
  helm upgrade --install "${AGENT_RELEASE}" "${CHART_DIR}/envpilot-agent" \
    --namespace "${NAMESPACE}" \
    "${helm_set_args[@]}"
  kubectl rollout status "deployment/envpilot-agent" -n "${NAMESPACE}" --timeout=240s
}

install_runner() {
  helm_set_args=()
  add_set "image.repository" "${RUNNER_IMAGE}"
  add_set "image.tag" "${RUNNER_IMAGE_TAG}"
  add_set "image.pullPolicy" "${IMAGE_PULL_POLICY}"
  add_set "imagePullSecrets[0].name" "${GHCR_SECRET}"
  add_set "controlPlane.url" "http://envpilot-control-plane.${NAMESPACE}.svc.cluster.local:8080"
  add_set "controlPlane.existingSecret" "envpilot-runner-bootstrap"
  add_set "project.id" "${PROJECT_ID}"
  add_set "project.clusterId" "${CLUSTER_ID}"
  add_set "project.runnerId" "${RUNNER_ID}"
  add_set "project.namespace" "${RUNNER_NAMESPACE}"
  add_set "project.deploymentMode" "${DEPLOYMENT_MODE}"
  add_set "project.configUrl" "http://envpilot-control-plane.${NAMESPACE}.svc.cluster.local:8080/api/v1/projects/${PROJECT_ID}/runner-config"
  add_set "dependencyWait.enabled" "true"
  add_set "dependencyWait.healthPath" "/api/v1/health"
  add_set "controlPlane.authPersistence.createClaim" "true"
  if [[ -n "${STORAGE_CLASS}" ]]; then
    add_set "controlPlane.authPersistence.storageClassName" "${STORAGE_CLASS}"
  fi
  add_set "controlPlane.authPersistence.size" "1Mi"
  add_set "controlPlane.authPersistence.accessModes[0]" "ReadWriteOnce"
  add_common_scheduling_values ""
  helm upgrade --install "${RUNNER_RELEASE}" "${CHART_DIR}/envpilot-runner" \
    --namespace "${NAMESPACE}" \
    "${helm_set_args[@]}"
  kubectl rollout status "deployment/envpilot-runner-chart" -n "${NAMESPACE}" --timeout=240s
}

start_frontend_access() {
  if [[ "${FRONTEND_ACCESS_MODE}" != "nodeport" ]]; then
    echo "Browser UI: ingress mode enabled; use the configured ingress hostname."
    return 0
  fi

  if ! command -v minikube >/dev/null 2>&1; then
    echo "Browser UI is exposed as NodePort, but minikube is unavailable. Run:" >&2
    echo "  kubectl get svc -n ${NAMESPACE} ${FRONTEND_SERVICE}" >&2
    return 0
  fi
  if [[ -z "${MINIKUBE_PROFILE}" ]]; then
    MINIKUBE_PROFILE="$(kubectl config current-context 2>/dev/null || true)"
  fi
  if [[ -z "${MINIKUBE_PROFILE}" ]]; then
    echo "Browser UI is exposed as NodePort. Set ENVPILOT_MINIKUBE_PROFILE and rerun the service command." >&2
    return 0
  fi

  if [[ -f "${FRONTEND_ACCESS_PID_FILE}" ]]; then
    local old_pid
    old_pid="$(cat "${FRONTEND_ACCESS_PID_FILE}" 2>/dev/null || true)"
    [[ -z "${old_pid}" ]] || kill "${old_pid}" >/dev/null 2>&1 || true
  fi
  : >"${FRONTEND_ACCESS_LOG}"
  nohup minikube -p "${MINIKUBE_PROFILE}" service -n "${NAMESPACE}" "${FRONTEND_SERVICE}" --url --wait=5 >"${FRONTEND_ACCESS_LOG}" 2>&1 &
  local access_pid="$!"
  printf '%s\n' "${access_pid}" >"${FRONTEND_ACCESS_PID_FILE}"

  local browser_url=""
  for _ in $(seq 1 30); do
    browser_url="$(sed -n 's#^\(https\?://[^[:space:]]*\).*#\1#p' "${FRONTEND_ACCESS_LOG}" | head -n 1)"
    if [[ -n "${browser_url}" ]] && curl -fsS --max-time 3 "${browser_url}/" >/dev/null 2>&1; then
      echo "Browser UI: ${browser_url}"
      echo "Stop local frontend tunnel: kill ${access_pid}"
      return 0
    fi
    sleep 1
  done
  echo "frontend NodePort was created, but minikube tunnel did not become reachable" >&2
  echo "Run: minikube -p ${MINIKUBE_PROFILE} service -n ${NAMESPACE} ${FRONTEND_SERVICE} --url" >&2
  cat "${FRONTEND_ACCESS_LOG}" >&2 || true
  return 1
}

require_cmd kubectl
require_cmd helm
require_cmd curl
require_cmd jq
require_cmd sed

case "${MODE}" in
  clean-install)
    clean_namespace
    ;;
  install)
    ;;
  *)
    echo "usage: $0 [install|clean-install]" >&2
    exit 1
    ;;
esac

create_namespace_and_pull_secret
install_control_plane
start_port_forward
verify_api_capabilities
create_bootstrap_secrets
install_agent
install_runner

kubectl get pods,pvc -n "${NAMESPACE}"
start_frontend_access
