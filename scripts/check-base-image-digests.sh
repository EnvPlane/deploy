#!/usr/bin/env bash
set -euo pipefail

values="deploy/helm/envpilot/values.yaml"
for digest in \
  "$(yq -r '.["envpilot-control-plane"].postgres.image.digest' "$values")" \
  "$(yq -r '.["envpilot-control-plane"].redis.image.digest' "$values")"; do
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "image digest is not immutable: $digest" >&2
    exit 1
  }
done

echo "base image digest check passed"
