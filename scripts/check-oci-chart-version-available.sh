#!/usr/bin/env bash
set -euo pipefail
repository=""
version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository) repository="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    *) echo "usage: $0 --repository oci://... --version X.Y.Z" >&2; exit 2 ;;
  esac
done
[[ "$repository" =~ ^oci://ghcr\.io/envpilot/[a-z0-9-]+$ ]] || { echo "invalid canonical chart repository" >&2; exit 2; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || { echo "invalid chart version" >&2; exit 2; }
if helm show chart "$repository:$version" >/dev/null 2>&1; then
  echo "OCI chart version already exists: $repository:$version" >&2
  exit 1
fi
echo "OCI chart version is available: $repository:$version"
