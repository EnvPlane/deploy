#!/usr/bin/env bash
# Render-only operator preview. Normal control-plane reconciliation owns apply.
set -euo pipefail
renderer="${ENVPLANE_PVC_COPY_PROFILE_RENDERER:-envplane-pvc-copy-source-profile}"
format=review
input=""
while (($#)); do
  case "$1" in
    --renderer) renderer="${2:?renderer path required}"; shift 2 ;;
    --format) format="${2:?format required}"; shift 2 ;;
    --input) input="${2:?metadata JSON path required}"; shift 2 ;;
    -h|--help) echo 'Render metadata only: --renderer BIN --format review|manifests|values|env [--input JSON]'; exit 0 ;;
    *) echo 'Unsupported source profile render option' >&2; exit 2 ;;
  esac
done
case "$format" in review|manifests|values|env) ;; *) echo 'Unsupported source profile format' >&2; exit 2 ;; esac
if ! command -v "$renderer" >/dev/null 2>&1; then
  echo 'Build/install control-plane/apps/pvc-copy-source-profile or set ENVPLANE_PVC_COPY_PROFILE_RENDERER' >&2
  exit 1
fi
if [[ -n "$input" ]]; then exec "$renderer" -format "$format" < "$input"; fi
exec "$renderer" -format "$format"
