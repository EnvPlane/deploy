#!/usr/bin/env bash
# Bring up the EnvPilot control plane (API + frontend + Postgres + Redis)
# in a local minikube cluster, from the multi-repo workspace layout:
#
#   PROJECTS/envpilot/
#     control-plane/   <- API image source
#     frontend/        <- UI image source
#     deploy/          <- this repo (helm charts + scripts)
#
# Usage: ./scripts/minikube-up.sh
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="${ENVPILOT_WORKSPACE_ROOT:-$(cd "$DEPLOY_ROOT/.." && pwd)}"
CONTROL_PLANE_DIR="${ENVPILOT_CONTROL_PLANE_DIR:-$WORKSPACE_ROOT/control-plane}"
FRONTEND_DIR="${ENVPILOT_FRONTEND_DIR:-$WORKSPACE_ROOT/frontend}"

PROFILE="${MINIKUBE_PROFILE:-envpilot}"
NAMESPACE="${ENVPILOT_NAMESPACE:-envpilot}"
RELEASE="${ENVPILOT_RELEASE:-envpilot}"
CHART="$DEPLOY_ROOT/deploy/helm/envpilot-control-plane"
VALUES="$CHART/values-minikube.yaml"
DOMAIN="envpilot.local"

log() { printf '\n==> %s\n' "$*"; }

# --- prerequisites ---------------------------------------------------------
for bin in minikube kubectl helm docker; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required but not installed." >&2; exit 1; }
done
[[ -f "$CONTROL_PLANE_DIR/Dockerfile" ]] || { echo "ERROR: control-plane repo not found at $CONTROL_PLANE_DIR" >&2; exit 1; }
[[ -f "$FRONTEND_DIR/Dockerfile" ]]      || { echo "ERROR: frontend repo not found at $FRONTEND_DIR" >&2; exit 1; }

# --- cluster ---------------------------------------------------------------
if minikube -p "$PROFILE" status >/dev/null 2>&1; then
  log "minikube profile '$PROFILE' already running"
else
  log "Starting minikube profile '$PROFILE'"
  minikube start -p "$PROFILE" --cpus=4 --memory=6g
fi

log "Enabling ingress addon"
minikube -p "$PROFILE" addons enable ingress

# --- images ----------------------------------------------------------------
# Build inside the minikube docker daemon so no registry is needed.
log "Switching docker context to minikube"
eval "$(minikube -p "$PROFILE" docker-env)"

log "Building API image envpilot/api:local from $CONTROL_PLANE_DIR"
docker build -t envpilot/api:local "$CONTROL_PLANE_DIR"

log "Building frontend image envpilot/frontend:local from $FRONTEND_DIR"
docker build -t envpilot/frontend:local "$FRONTEND_DIR"

# --- deploy ----------------------------------------------------------------
log "Installing helm release '$RELEASE' into namespace '$NAMESPACE'"
helm upgrade --install "$RELEASE" "$CHART" \
	--kube-context "$PROFILE" \
  --namespace "$NAMESPACE" --create-namespace \
  -f "$VALUES" \
  --wait --timeout 10m

# Local images retain the :local tag. Helm does not change the pod template
# when only the image bytes change, so force the workloads to pick up the
# newly built images on every local rebuild.
kubectl --context "$PROFILE" -n "$NAMESPACE" rollout restart deployment/envpilot-control-plane deployment/envpilot-control-plane-frontend

log "Waiting for rollout"
kubectl --context "$PROFILE" -n "$NAMESPACE" rollout status deployment/envpilot-control-plane --timeout=5m
kubectl --context "$PROFILE" -n "$NAMESPACE" rollout status deployment/envpilot-control-plane-frontend --timeout=5m
kubectl --context "$PROFILE" -n "$NAMESPACE" get pods,svc,ingress,pvc

# --- access ----------------------------------------------------------------
cat <<EOF

EnvPilot control plane is deployed.

Note: the agent and runner services are not installed here — their repos do not
yet ship a Dockerfile. For the full stack against a real registry use
scripts/envpilot-clean-install.sh.

Access option 1 (port-forward, simplest):
  kubectl --context $PROFILE -n $NAMESPACE port-forward svc/envpilot-control-plane 8080:8080
  open http://localhost:8080

Access option 2 (ingress):
  1. echo "127.0.0.1 $DOMAIN" | sudo tee -a /etc/hosts
  2. minikube -p $PROFILE tunnel      # keep running in a separate terminal
  3. open http://$DOMAIN

Verify:    ./scripts/minikube-verify.sh
Tear down: ./scripts/minikube-down.sh
EOF
