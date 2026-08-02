#!/usr/bin/env bash
# Retired compatibility entry point.
#
# Remote Agent and Runner installations require a stable control-plane endpoint
# reachable from target pods. This script intentionally does not create a
# port-forward, tunnel, chart server, or cluster because those make readiness
# depend on a developer process.
set -euo pipefail

echo "ERROR: minikube-agent-access.sh is retired. Configure ENVPILOT_REMOTE_CONTROL_PLANE_URL (and optional CA Secret/key) on the control plane, then use generated remote bootstrap instructions." >&2
exit 2
