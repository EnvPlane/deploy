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

chart_field() {
  local chart="$1"
  local field="$2"
  helm show chart "$chart" | awk -F': ' -v key="$field" '$1 == key {print $2; exit}'
}

check_file_dependencies() {
  local chart_dir="$1"
  local packages_dir="$chart_dir/charts"
  [[ -f "$chart_dir/Chart.yaml" ]] || return 0
  [[ -d "$packages_dir" ]] || return 0

  while IFS=$'\t' read -r dependency_name dependency_version dependency_repository; do
    [[ -n "$dependency_name" ]] || continue
    [[ "$dependency_repository" == file://* ]] || continue
    archive="$packages_dir/$dependency_name-$dependency_version.tgz"
    [[ -f "$archive" ]] || {
      echo "packaged file dependency is missing: $archive" >&2
      exit 1
    }
    source_dir="$deploy_root/deploy/helm/$dependency_name"
    [[ -d "$source_dir" ]] || {
      echo "canonical source for packaged dependency is missing: $source_dir" >&2
      exit 1
    }
    package_name="$(chart_field "$archive" name)"
    package_version="$(chart_field "$archive" version)"
    source_version="$(chart_field "$source_dir" version)"
    [[ "$package_name" == "$dependency_name" && "$package_version" == "$dependency_version" && "$source_version" == "$dependency_version" ]] || {
      echo "packaged dependency version drift: chart=$chart_dir dependency=$dependency_name declared=$dependency_version package=$package_name@$package_version source=$source_version" >&2
      exit 1
    }
  done < <(awk '
    /^  - name:/ { name=$3; version=""; repository="" }
    /^    version:/ { version=$2 }
    /^    repository:/ { repository=$2; if (repository ~ /^file:\/\//) print name "\t" version "\t" repository }
  ' "$chart_dir/Chart.yaml")
}

for chart_dir in "$deploy_root"/deploy/helm/*; do
  check_file_dependencies "$chart_dir"
done

umbrella_render="$tmp_dir/umbrella-render.yaml"
helm template envplane "$umbrella" --set envplane-control-plane.postgres.tls.enabled=false >"$umbrella_render"
for env_name in ENVPLANE_WEBHOOK_RECEIVER_STATUS_CONFIGMAP ENVPLANE_WEBHOOK_RECEIVER_STATUS_NAMESPACE ENVPLANE_WEBHOOK_RECEIVER_STATUS_STALE_AFTER_SECONDS; do
  count="$(grep -c "name: $env_name$" "$umbrella_render" || true)"
  [[ "$count" == "1" ]] || {
    echo "umbrella must render exactly one $env_name, got $count" >&2
    exit 1
  }
done
grep -q 'value: "{{ .Release.Name }}-webhook-receiver-status"' "$umbrella_render" && {
  echo "umbrella rendered an unresolved webhook status ConfigMap name" >&2
  exit 1
}
if grep -A1 'name: ENVPLANE_WEBHOOK_RECEIVER_STATUS_NAMESPACE$' "$umbrella_render" | grep -q 'value: ""'; then
  echo "umbrella rendered an empty webhook status namespace" >&2
  exit 1
fi

echo "vendored Helm chart drift check passed"
