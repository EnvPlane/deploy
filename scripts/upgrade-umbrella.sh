#!/usr/bin/env bash
set -euo pipefail

# Upgrade a published EnvPlane umbrella while retaining operator configuration.
#
# Helm --reuse-values preserves the complete nested values tree from the prior
# release. That silently retains old runtime image digests even when the new
# signed umbrella archive selects different immutable artifacts. This wrapper
# deliberately resets chart defaults, then layers the durable operator values
# file back on top. The packaged compatibility manifest rejects a conflicting
# image override before Helm changes the release.

release=""
chart="oci://ghcr.io/envplane/envplane"
version=""
namespace="envplane"
operator_values=""
kube_context=""
timeout="15m"
wait=true
create_namespace=false

usage() {
  cat <<'EOF'
Usage:
  scripts/upgrade-umbrella.sh --release NAME --version X.Y.Z \
    --operator-values PATH [--namespace NAME] [--chart OCI_REF] \
    [--kube-context CONTEXT] [--timeout DURATION] [--create-namespace] [--no-wait]

The operator values file contains only operator configuration, such as access,
database Secret references, resources and scheduling. Do not place image pins
or Secret values in it. The selected published umbrella archive supplies the
signed immutable image pins.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) release="${2:-}"; shift 2 ;;
    --chart) chart="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --namespace) namespace="${2:-}"; shift 2 ;;
    --operator-values) operator_values="${2:-}"; shift 2 ;;
    --kube-context) kube_context="${2:-}"; shift 2 ;;
    --timeout) timeout="${2:-}"; shift 2 ;;
    --create-namespace) create_namespace=true; shift ;;
    --no-wait) wait=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$release" ]] || { echo "--release is required" >&2; exit 2; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "--version must be immutable umbrella SemVer X.Y.Z" >&2; exit 2; }
[[ -f "$operator_values" ]] || { echo "--operator-values must name an existing durable values file" >&2; exit 2; }

args=(upgrade --install "$release" "$chart" --version "$version" --namespace "$namespace" --values "$operator_values" --reset-values --timeout "$timeout")
[[ -n "$kube_context" ]] && args+=(--kube-context "$kube_context")
[[ "$create_namespace" == true ]] && args+=(--create-namespace)
[[ "$wait" == true ]] && args+=(--wait)

# Do not echo values. They may contain existing Secret references, and callers
# remain responsible for keeping credential material out of the file.
exec helm "${args[@]}"
