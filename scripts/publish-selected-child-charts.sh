#!/usr/bin/env bash
# Publish the immutable child-chart versions selected by the umbrella source.
#
# A stable umbrella dependency must never rely on a manually created Git tag.
# This script is deliberately driven by the versions committed in the umbrella
# Chart.yaml: it verifies that every canonical child Chart.yaml agrees, reuses
# an already-published immutable version, or publishes and attests the exact
# selected version before the compatibility manifest is resolved.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: publish-selected-child-charts.sh --umbrella-chart <path> --charts-dir <path> \
  --dist <directory> --output <file> [--owner <owner>] [--source-revision <sha>]

Requires Helm, ORAS, cosign and jq. Helm and ORAS must already be authenticated
to the target OCI registry.
EOF
  exit 2
}

umbrella_chart=""
charts_dir=""
dist=""
output=""
owner="envpilot"
source_revision="${GITHUB_SHA:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --umbrella-chart) umbrella_chart="${2:-}"; shift 2 ;;
    --charts-dir) charts_dir="${2:-}"; shift 2 ;;
    --dist) dist="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    --owner) owner="${2:-}"; shift 2 ;;
    --source-revision) source_revision="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -f "$umbrella_chart" ]] || { echo "umbrella Chart.yaml not found: $umbrella_chart" >&2; exit 2; }
[[ -d "$charts_dir" ]] || { echo "canonical chart directory not found: $charts_dir" >&2; exit 2; }
[[ -n "$dist" && -n "$output" ]] || usage
[[ "$owner" =~ ^[A-Za-z0-9-]+$ ]] || { echo "invalid OCI owner" >&2; exit 2; }
if [[ ! "$source_revision" =~ ^[0-9a-f]{40}$ ]]; then
  source_revision="$(git -C "$(dirname "$umbrella_chart")/../.." rev-parse HEAD 2>/dev/null || true)"
fi
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { echo "source revision is unavailable" >&2; exit 2; }
for command in helm oras cosign jq; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done

dependency_version() {
  local chart="$1"
  awk -v chart="$chart" '
    $0 == "  - name: " chart { in_dependency=1; next }
    in_dependency && /^  - name: / { exit }
    in_dependency && /^    version: / { print $2; exit }
  ' "$umbrella_chart"
}

chart_version() {
  awk '/^version:/{print $2; exit}' "$1/Chart.yaml"
}

is_not_found() {
  grep -Eqi 'manifest unknown|not found|404|name unknown' <<<"$1"
}

is_auth_error() {
  grep -Eqi 'unauthorized|authentication required|denied|forbidden|401|403' <<<"$1"
}

mkdir -p "$dist" "$(dirname "$output")"
entries=()
for mapping in \
  control-plane:envpilot-control-plane \
  frontend:envpilot-frontend \
  agent:envpilot-agent \
  runner:envpilot-runner; do
  component="${mapping%%:*}"
  chart="${mapping##*:}"
  selected_version="$(dependency_version "$chart")"
  child_dir="$charts_dir/$chart"
  [[ "$selected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "umbrella dependency $chart must select a stable SemVer; got ${selected_version:-<missing>}" >&2
    exit 1
  }
  [[ -f "$child_dir/Chart.yaml" ]] || { echo "canonical child Chart.yaml is missing: $child_dir/Chart.yaml" >&2; exit 1; }
  child_version="$(chart_version "$child_dir")"
  [[ "$child_version" == "$selected_version" ]] || {
    echo "umbrella selects $chart:$selected_version but canonical child is $child_version; bump the child chart or update the dependency together" >&2
    exit 1
  }

  repository="oci://ghcr.io/$owner/$chart"
  oras_repository="${repository#oci://}"
  publication="existing"
  descriptor=""
  if ! descriptor="$(oras manifest fetch --descriptor "$oras_repository:$selected_version" 2>&1)"; then
    if is_auth_error "$descriptor"; then
      echo "cannot verify required child chart $repository:$selected_version: registry authentication failed" >&2
      exit 1
    fi
    if ! is_not_found "$descriptor"; then
      echo "cannot verify required child chart $repository:$selected_version: $descriptor" >&2
      exit 1
    fi

    publication="published"
    helm dependency build --skip-refresh "$child_dir"
    helm lint "$child_dir"
    package="$dist/$chart-$selected_version.tgz"
    rm -f "$package"
    helm package "$child_dir" --destination "$dist" >/dev/null
    [[ -f "$package" ]] || { echo "failed to package required child chart $chart:$selected_version" >&2; exit 1; }
    push_output="$(helm push "$package" "oci://ghcr.io/$owner" 2>&1)"
    printf '%s\n' "$push_output" >&2
    digest="$(awk '/^Digest:/{print $2; exit}' <<<"$push_output")"
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
      echo "failed to publish required child chart $repository:$selected_version with an immutable digest" >&2
      exit 1
    }

    predicate="$dist/$chart-$selected_version.attestation.json"
    jq -n \
      --arg chart "$chart" \
      --arg version "$selected_version" \
      --arg digest "$digest" \
      --arg sourceRevision "$source_revision" \
      '{schemaVersion:1,artifactType:"helm-chart",chart:$chart,version:$version,digest:$digest,sourceRevision:$sourceRevision}' \
      > "$predicate"
    cosign sign --yes "$oras_repository@$digest"
    cosign attest --yes --predicate "$predicate" --type https://envpilot.dev/chart/v1 "$oras_repository@$digest"
  else
    digest="$(jq -er '.digest' <<<"$descriptor")"
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
      echo "registry returned an invalid descriptor for required child chart $repository:$selected_version" >&2
      exit 1
    }
    metadata="$(helm show chart "$repository:$selected_version" 2>&1)" || {
      echo "required child chart is not readable after descriptor resolution: $repository:$selected_version" >&2
      exit 1
    }
    grep -Fxq "name: $chart" <<<"$metadata" || { echo "required chart has unexpected name: $repository:$selected_version" >&2; exit 1; }
    grep -Fxq "version: $selected_version" <<<"$metadata" || { echo "required chart has unexpected version: $repository:$selected_version" >&2; exit 1; }
  fi

  entries+=("$(jq -cn \
    --arg component "$component" \
    --arg chart "$chart" \
    --arg repository "$repository" \
    --arg version "$selected_version" \
    --arg digest "$digest" \
    --arg sourceRevision "$source_revision" \
    --arg publication "$publication" \
    '{component:$component,chart:$chart,repository:$repository,version:$version,digest:$digest,sourceRevision:$sourceRevision,publication:$publication}')")
done

printf '%s\n' "${entries[@]}" | jq -s \
  --arg sourceRevision "$source_revision" \
  '{schemaVersion:1,sourceRevision:$sourceRevision,childCharts:.}' > "$output"
jq -e '(.childCharts | length == 4) and all(.childCharts[]; (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and (.digest | test("^sha256:[0-9a-f]{64}$")))' "$output" >/dev/null
echo "confirmed canonical child charts: $output"
