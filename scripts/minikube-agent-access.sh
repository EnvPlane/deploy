#!/usr/bin/env bash
# Make a local EnvPilot control plane reachable from an agent installed in a
# different minikube profile. The script also publishes the checked-out agent
# chart to the local Helm client and transfers the local control-plane, Agent,
# and Runner images to the target profile.
#
# Usage:
#   ./scripts/minikube-agent-access.sh start <target-profile>
#   ./scripts/minikube-agent-access.sh stop
#
# After start, select <target-profile> as the active kubectl context and run
# the exact commands displayed by the bootstrap wizard. Do not use
# envpilot.local from the target profile: it resolves to that profile's host.
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIR="$DEPLOY_ROOT/deploy/helm/envpilot-agent"
CONTROL_PROFILE="${ENVPILOT_CONTROL_MINIKUBE_PROFILE:-envpilot}"
NAMESPACE="${ENVPILOT_NAMESPACE:-envpilot}"
CONTROL_SERVICE="${ENVPILOT_CONTROL_PLANE_SERVICE:-envpilot-control-plane}"
ACCESS_DIR="${ENVPILOT_AGENT_ACCESS_DIR:-${TMPDIR:-/tmp}/envpilot-agent-access}"
CONTROL_PORT="${ENVPILOT_AGENT_CONTROL_PLANE_PORT:-18080}"
CHART_PORT="${ENVPILOT_AGENT_CHART_PORT:-18081}"

action="${1:-start}"
target_profile="${2:-${ENVPILOT_AGENT_TARGET_MINIKUBE_PROFILE:-}}"
port_forward_pid="$ACCESS_DIR/control-plane-port-forward.pid"
chart_server_pid="$ACCESS_DIR/chart-server.pid"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

stop_process() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(<"$pid_file")"
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" || true
    fi
    rm -f "$pid_file"
  fi
}

case "$action" in
  stop)
    stop_process "$port_forward_pid"
    stop_process "$chart_server_pid"
    log "Stopped local agent access helpers."
    exit 0
    ;;
  start) ;;
  *) die "usage: $0 start <target-profile> | stop" ;;
esac

[[ -n "$target_profile" ]] || die "target minikube profile is required"
for bin in minikube kubectl helm python3 curl; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required"
done
[[ -d "$CHART_DIR" ]] || die "agent chart is missing at $CHART_DIR"
minikube -p "$CONTROL_PROFILE" status >/dev/null || die "control profile '$CONTROL_PROFILE' is not running"
minikube -p "$target_profile" status >/dev/null || die "target profile '$target_profile' is not running"

mkdir -p "$ACCESS_DIR"
rm -f "$ACCESS_DIR/envpilot-agent-"*.tgz

log "Packaging the local agent chart"
helm package "$CHART_DIR" --destination "$ACCESS_DIR" >/dev/null
chart_archive="$(find "$ACCESS_DIR" -maxdepth 1 -type f -name 'envpilot-agent-*.tgz' -print -quit)"
[[ -n "$chart_archive" && -f "$chart_archive" ]] || die "agent chart package was not created"

for image in envpilot/api:local envpilot/agent:local envpilot/runner:local; do
  image_file="$(printf '%s' "$image" | tr '/:' '__')"
  image_archive="$ACCESS_DIR/${image_file}.tar"
  log "Copying $image to minikube profile '$target_profile'"
  minikube -p "$CONTROL_PROFILE" image save "$image" "$image_archive"
  minikube -p "$target_profile" image load "$image_archive"
done

stop_process "$port_forward_pid"
stop_process "$chart_server_pid"

log "Starting a control-plane gateway on host port $CONTROL_PORT"
nohup kubectl --context "$CONTROL_PROFILE" -n "$NAMESPACE" port-forward --address 0.0.0.0 "svc/$CONTROL_SERVICE" "$CONTROL_PORT:8080" >"$ACCESS_DIR/control-plane-port-forward.log" 2>&1 &
echo $! >"$port_forward_pid"

log "Serving the packaged agent chart on http://127.0.0.1:$CHART_PORT"
nohup python3 -m http.server "$CHART_PORT" --bind 127.0.0.1 --directory "$ACCESS_DIR" >"$ACCESS_DIR/chart-server.log" 2>&1 &
echo $! >"$chart_server_pid"

sleep 2
kill -0 "$(<"$port_forward_pid")" >/dev/null 2>&1 || die "control-plane gateway did not start; see $ACCESS_DIR/control-plane-port-forward.log"
kill -0 "$(<"$chart_server_pid")" >/dev/null 2>&1 || die "chart server did not start; see $ACCESS_DIR/chart-server.log"
curl --fail --silent --show-error "http://127.0.0.1:$CONTROL_PORT/api/v1/health" >/dev/null || die "control-plane gateway health check failed"

cat <<EOF

Local multi-cluster agent access is ready.

1. Switch Helm/kubectl to the target profile:
   kubectl config use-context $target_profile

2. In the bootstrap wizard, generate the agent commands and run them unchanged.
   The displayed preflight runs inside $target_profile against:
   http://host.minikube.internal:$CONTROL_PORT/api/v1/health

3. Keep this terminal helper running until the agent is connected. Stop it with:
   $0 stop
EOF
