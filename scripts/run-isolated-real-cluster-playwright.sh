#!/usr/bin/env bash
set -euo pipefail

# Reusable two-Kind-cluster browser gate. Renew its private test endpoint before
# invoking Playwright, so an expired fixture certificate cannot masquerade as
# an application readiness or authentication failure.
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ENVPLANE_E2E_STORAGE_STATE:?set a fresh local Playwright storageState file}"
[[ -s "$ENVPLANE_E2E_STORAGE_STATE" ]] || { echo 'Playwright storageState file is missing or empty' >&2; exit 2; }
: "${ENVPLANE_E2E_BASE_URL:?set the isolated frontend URL}"
: "${ENVPLANE_E2E_API_URL:?set the isolated API URL}"

"$script_directory/ensure-isolated-e2e-tls.sh" ensure
"$script_directory/ensure-isolated-e2e-tls.sh" check
ENVPLANE_DISABLE_WEB_SERVER=1 ENVPLANE_E2E_REAL_CLUSTER=1 \
  npm --prefix "$script_directory/../../frontend" run test:e2e:real -- "$@"
