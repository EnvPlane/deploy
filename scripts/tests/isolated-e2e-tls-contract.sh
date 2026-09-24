#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$script_directory/ensure-isolated-e2e-tls.sh"
runner="$script_directory/run-isolated-real-cluster-playwright.sh"
temporary_directory="$(mktemp -d /tmp/envplane-e2e-tls-contract.XXXXXX)"
trap 'rm -f "$temporary_directory/short.crt" "$temporary_directory/short.key" "$temporary_directory/fresh.crt" "$temporary_directory/fresh.key"; rmdir "$temporary_directory"' EXIT
chmod 700 "$temporary_directory"

openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes \
  -keyout "$temporary_directory/short.key" -out "$temporary_directory/short.crt" \
  -subj '/CN=management.e2e.internal' -addext 'subjectAltName=DNS:management.e2e.internal' >/dev/null 2>&1
if ENVPLANE_E2E_TLS_MIN_VALID_SECONDS=172800 bash "$helper" check-file "$temporary_directory/short.crt" management.e2e.internal >"/dev/null" 2>&1; then
  echo 'short-lived certificate was not rejected before Playwright' >&2
  exit 1
fi
openssl req -x509 -newkey rsa:2048 -sha256 -days 30 -nodes \
  -keyout "$temporary_directory/fresh.key" -out "$temporary_directory/fresh.crt" \
  -subj '/CN=management.e2e.internal' -addext 'subjectAltName=DNS:management.e2e.internal' >/dev/null 2>&1
ENVPLANE_E2E_TLS_MIN_VALID_SECONDS=172800 bash "$helper" check-file "$temporary_directory/fresh.crt" management.e2e.internal >"/dev/null"
if ENVPLANE_E2E_TLS_MIN_VALID_SECONDS=172800 bash "$helper" check-file "$temporary_directory/fresh.crt" wrong.e2e.internal >"/dev/null" 2>&1; then
  echo 'certificate with the wrong SAN was accepted' >&2
  exit 1
fi

grep -Fq 'apply_all_ca_secrets "$temporary_directory/bundle.crt"' "$helper"
grep -Fq 'rollout restart "deployment/$endpoint_deployment"' "$helper"
grep -Fq 'restart_remote_deployments' "$helper"
grep -Fq 'ensure-isolated-e2e-tls.sh" ensure' "$runner"
grep -Fq 'ensure-isolated-e2e-tls.sh" check' "$runner"
echo 'isolated E2E TLS contract passed'
