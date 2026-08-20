#!/usr/bin/env bash
set -euo pipefail

# Verify that every vendored umbrella dependency is byte-for-byte equivalent
# to the canonical chart source used to build it.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
deploy_root="$(cd "$script_dir/.." && pwd)"
umbrella="$deploy_root/deploy/helm/envplane"
vendor_dir="$umbrella/charts"

command -v tar >/dev/null || { echo "tar is required" >&2; exit 1; }
command -v helm >/dev/null || { echo "helm is required" >&2; exit 1; }
[[ -d "$vendor_dir" ]] || { echo "vendored chart directory is missing: $vendor_dir" >&2; exit 1; }

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

found=0
while IFS= read -r archive; do
  found=1
  archive_name="$(basename "$archive")"
  archive_tmp="$tmp_dir/${archive_name%.tgz}"
  mkdir -p "$archive_tmp"
  tar -xzf "$archive" -C "$archive_tmp"
  chart_dir="$(find "$archive_tmp" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [[ -n "$chart_dir" ]] || { echo "archive has no chart directory: $archive" >&2; exit 1; }
  chart_name="$(basename "$chart_dir")"
  source_dir="$deploy_root/deploy/helm/$chart_name"
  [[ -d "$source_dir" ]] || { echo "missing canonical source for $chart_name" >&2; exit 1; }

  # Helm rewrites Chart.yaml formatting while packaging. Compare its parsed
  # representation, then compare all payload files byte-for-byte.
  if ! diff -u <(helm show chart "$source_dir") <(helm show chart "$archive"); then
    echo "vendored chart metadata drift detected: $archive_name" >&2
    exit 1
  fi
  if ! diff -ru --exclude='.git' --exclude='Chart.yaml' --exclude='.helmignore' --exclude='charts' --exclude='tmpcharts-*' "$source_dir" "$chart_dir"; then
    echo "vendored chart drift detected: $archive_name" >&2
    exit 1
  fi
done < <(find "$vendor_dir" -maxdepth 1 -type f -name '*.tgz' -print | sort)

(( found == 1 )) || { echo "no vendored chart archives found" >&2; exit 1; }
echo "vendored Helm chart drift check passed"
