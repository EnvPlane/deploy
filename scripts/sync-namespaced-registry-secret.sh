#!/usr/bin/env bash
set -euo pipefail

# Copies a dockerconfigjson Secret between namespaces without printing it or
# placing credential material in Helm values. This is an operator-only setup
# operation: EnvPlane charts and the control plane consume only Secret names.

context=""
source_namespace="envplane"
target_namespace="envplane-executors"
secret_name="envplane-ghcr"

usage() {
  cat <<'EOF'
usage: sync-namespaced-registry-secret.sh [options]

Copy an existing kubernetes.io/dockerconfigjson Secret to another namespace.
Credential data is streamed directly from kubectl to kubectl and is never
printed or written to disk.

Options:
  --context NAME             Kubernetes context (default: current context)
  --source-namespace NAME    Source namespace (default: envplane)
  --target-namespace NAME    Target namespace (default: envplane-executors)
  --secret NAME              Secret name in both namespaces (default: envplane-ghcr)
  -h, --help                 Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) context="$2"; shift 2 ;;
    --source-namespace) source_namespace="$2"; shift 2 ;;
    --target-namespace) target_namespace="$2"; shift 2 ;;
    --secret) secret_name="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in "$source_namespace" "$target_namespace" "$secret_name"; do
  [[ -n "$value" ]] || { echo "namespace and Secret name must not be empty" >&2; exit 2; }
done
for bin in jq kubectl; do
  command -v "$bin" >/dev/null || { echo "missing required command: $bin" >&2; exit 2; }
done

kubectl_args=()
if [[ -n "$context" ]]; then
  kubectl_args+=(--context "$context")
fi

# Server-side apply deliberately has no --force-conflicts. A conflicting
# target Secret requires an explicit operator decision rather than overwriting
# credentials owned by another controller.
kubectl "${kubectl_args[@]}" -n "$source_namespace" get secret "$secret_name" -o json |
  jq --arg namespace "$target_namespace" --arg name "$secret_name" --arg source "$source_namespace/$secret_name" '
    if .type != "kubernetes.io/dockerconfigjson" then
      error("source Secret must have type kubernetes.io/dockerconfigjson")
    elif (.data[".dockerconfigjson"] | type) != "string" or (.data[".dockerconfigjson"] | length) == 0 then
      error("source Secret must contain a non-empty .dockerconfigjson key")
    else
      {
        apiVersion: "v1",
        kind: "Secret",
        metadata: {
          name: $name,
          namespace: $namespace,
          labels: {
            "app.kubernetes.io/managed-by": "envplane-registry-secret-sync",
            "envplane.io/source-secret": $source
          }
        },
        type: .type,
        data: {".dockerconfigjson": .data[".dockerconfigjson"]}
      }
    end
  ' |
  kubectl "${kubectl_args[@]}" apply --server-side --field-manager=envplane-registry-secret-sync -f - >/dev/null

echo "synchronized $source_namespace/$secret_name to $target_namespace/$secret_name without printing credential data"
