#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/scripts/published-remote-cluster-lifecycle-e2e.sh"

bash -n "$script"
for expected in \
  'compatibility_fingerprint' \
  'observed_generation' \
  'request_action migrate' \
  'X DELETE' \
  'auth PVCs' \
  'never creates a cluster'; do
  grep -Fq "$expected" "$script"
done

if grep -Eq 'host\.minikube\.internal|port-forward|minikube[[:space:]]+start|kubectl.*create.*cluster' "$script"; then
  echo "published remote lifecycle E2E must not special-case local cluster transport" >&2
  exit 1
fi

echo 'published remote cluster lifecycle contract is valid'
