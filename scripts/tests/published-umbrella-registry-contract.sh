#!/usr/bin/env bash
set -euo pipefail

# Cluster-free published-artifact contract test. It verifies that a released
# umbrella carries the shared registry Secret reference into every runtime
# workload, while the chart itself never contains credential data.
CHART_REF="${CHART_REF:-oci://ghcr.io/envplane/envplane}"
VERSION="${1:-${ENVPLANE_UMBRELLA_VERSION:-}}"
SECRET_NAME="${REGISTRY_SECRET_NAME:-registry-credentials}"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <umbrella-version> (or ENVPLANE_UMBRELLA_VERSION)" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

rendered="$tmp/rendered.yaml"
helm template envplane "$CHART_REF" --version "$VERSION" \
  --set global.envplane.registry.mode=existing \
  --set global.envplane.registry.existingSecret="$SECRET_NAME" \
  --set agent.enabled=true --set runner.enabled=true \
  >"$rendered"

for expected in \
  "envplane/templates/registry-preflight-job.yaml" \
  "envplane/charts/envplane-control-plane/templates/deployment.yaml" \
  "envplane/charts/envplane-frontend/templates/deployment.yaml" \
  "envplane/charts/envplane-agent/templates/deployment.yaml" \
  "envplane/charts/envplane-runner/templates/deployment.yaml"; do
  rg -q "$expected" "$rendered" || { echo "published chart missing $expected" >&2; exit 1; }
done

count="$(rg -c --fixed-strings -- "- name: $SECRET_NAME" "$rendered" | awk -F: '{sum += $NF} END {print sum + 0}')"
(( count >= 5 )) || { echo "registry Secret reference propagated to only $count rendered pods" >&2; exit 1; }

if rg -q 'dockerconfigjson:|authorization: Basic' "$rendered"; then
  echo "published chart render contains possible registry credential data" >&2
  exit 1
fi

missing="$tmp/missing.out"
if helm template envplane "$CHART_REF" --version "$VERSION" \
  --set global.envplane.registry.mode=existing >"$missing" 2>&1; then
  echo "missing registry Secret reference unexpectedly passed schema validation" >&2
  exit 1
fi
rg -q 'registry.*existingSecret|existingSecret' "$missing" || {
  echo "missing registry Secret failure is not actionable" >&2
  exit 1
}

echo "published umbrella $VERSION registry contract passed"
