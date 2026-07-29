#!/usr/bin/env bash
# Tear down the EnvPilot control plane from the local minikube cluster.
# Usage: ./scripts/minikube-down.sh [--delete-cluster]
set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-envpilot}"
NAMESPACE="${ENVPILOT_NAMESPACE:-envpilot}"
RELEASE="${ENVPILOT_RELEASE:-envpilot}"

helm uninstall "$RELEASE" --namespace "$NAMESPACE" || true
kubectl delete namespace "$NAMESPACE" --ignore-not-found

if [[ "${1:-}" == "--delete-cluster" ]]; then
  minikube delete -p "$PROFILE"
fi
