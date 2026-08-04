#!/usr/bin/env bash
# Resolve exactly the immutable artifacts pinned by the deploy source tree.
#
# This deliberately does not scan GHCR for "latest" artifacts.  A release may
# only consume refs from the pinned source tree, already committed to
# values.yaml/Chart.yaml.  If
# a referenced artifact is still being published, wait for it and then verify
# the registry digest instead of silently falling back to an older image.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: resolve-latest-published-artifacts.sh --output <file> \
  --values-file <path> --chart-file <path> --selected-child-charts <file> \
  [--owner <owner>]

Requires Docker/Buildx and Helm registry authentication for artifact checks.
ENVPILOT_ARTIFACT_WAIT_ATTEMPTS and ENVPILOT_ARTIFACT_WAIT_SECONDS tune the
bounded wait for an image/chart publication still in progress.
EOF
  exit 2
}

owner="envpilot"
output=""
values_file=""
chart_file=""
selected_child_charts=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) owner="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    --values-file) values_file="${2:-}"; shift 2 ;;
    --chart-file) chart_file="${2:-}"; shift 2 ;;
    --selected-child-charts) selected_child_charts="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$owner" =~ ^[A-Za-z0-9-]+$ ]] || { echo "invalid owner" >&2; exit 2; }
[[ -n "$output" ]] || { echo "--output is required" >&2; exit 2; }
[[ -f "$values_file" ]] || { echo "values file not found: $values_file" >&2; exit 2; }
[[ -f "$chart_file" ]] || { echo "chart file not found: $chart_file" >&2; exit 2; }
[[ -f "$selected_child_charts" ]] || {
  echo "selected child-chart manifest is required; run Publish selected stable child charts first" >&2
  exit 2
}
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
command -v helm >/dev/null || { echo "helm is required" >&2; exit 1; }
command -v oras >/dev/null || { echo "oras is required" >&2; exit 1; }

wait_attempts="${ENVPILOT_ARTIFACT_WAIT_ATTEMPTS:-30}"
wait_seconds="${ENVPILOT_ARTIFACT_WAIT_SECONDS:-20}"
[[ "$wait_attempts" =~ ^[1-9][0-9]*$ && "$wait_seconds" =~ ^[0-9]+$ ]] || {
  echo "artifact wait settings must be positive integers" >&2; exit 2;
}

read_image_field() {
  local section="$1" field="$2"
  awk -v section="$section" -v field="$field" '
    $0 == section ":" { in_section=1; next }
    in_section && $0 ~ /^[^[:space:]]/ { exit }
    in_section && $0 == "  image:" { in_image=1; next }
    in_image && $0 ~ /^  [A-Za-z0-9][A-Za-z0-9_-]*:/ { exit }
    in_image && $0 ~ ("^    " field ":") {
      sub("^    " field ":[[:space:]]*", "")
      gsub(/"/, "")
      print
      exit
    }
  ' "$values_file"
}

verify_image() {
  local component="$1" repository="$2" tag="$3" expected_digest="$4" revision="$5"
  [[ "$repository" =~ ^ghcr\.io/envpilot/[a-z0-9-]+$ ]] || { echo "$component has invalid repository" >&2; exit 1; }
  [[ "$tag" == "sha-$revision" && "$revision" =~ ^[0-9a-f]{40}$ ]] || {
    echo "$component tag/sourceRevision mismatch" >&2; exit 1;
  }
  [[ "$expected_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "$component has invalid digest" >&2; exit 1; }
  local actual="" attempt
  for ((attempt=1; attempt<=wait_attempts; attempt++)); do
    actual="$(docker buildx imagetools inspect "$repository:$tag" 2>/dev/null \
      | awk '/^Digest:[[:space:]]+sha256:[0-9a-f]{64}$/ {print $2; exit}' || true)"
    if [[ "$actual" == "$expected_digest" ]]; then
      jq -cn --arg repository "$repository" --arg tag "$tag" \
        --arg digest "$expected_digest" --arg sourceRevision "$revision" \
        '{repository:$repository,tag:$tag,digest:$digest,sourceRevision:$sourceRevision}'
      return 0
    fi
    if (( attempt < wait_attempts )); then
      echo "waiting for $component artifact $repository:$tag (attempt $attempt/$wait_attempts)" >&2
      sleep "$wait_seconds"
    fi
  done
  echo "$component artifact was not published with expected digest: $repository:$tag@$expected_digest" >&2
  return 1
}

image_json() {
  local section="$1" component="$2" repository tag digest revision
  repository="$(read_image_field "$section" repository)"
  tag="$(read_image_field "$section" tag)"
  digest="$(read_image_field "$section" digest)"
  revision="$(read_image_field "$section" sourceRevision)"
  [[ -n "$repository" && -n "$tag" && -n "$digest" && -n "$revision" ]] || {
    echo "incomplete pinned image block for $component" >&2; exit 1;
  }
  verify_image "$component" "$repository" "$tag" "$digest" "$revision"
}

chart_version() {
  local name="$1"
  awk -v target="$name" '
    $1 == "-" && $2 == "name:" { found=($3 == target); next }
    found && $1 == "version:" { print $2; exit }
  ' "$chart_file"
}

chart_json() {
  local name="$1" package="$2" version selected expected_digest expected_repository descriptor actual_digest chart attempt
  version="$(chart_version "$name")"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "no pinned stable version for $name" >&2; exit 1;
  }
  selected="$(jq -cer --arg chart "$name" '.childCharts[] | select(.chart == $chart)' "$selected_child_charts")" || {
    echo "selected child-chart manifest does not contain $name" >&2; exit 1;
  }
  expected_repository="oci://ghcr.io/$owner/$package"
  expected_digest="$(jq -er '.digest' <<<"$selected")"
  jq -e --arg version "$version" --arg repository "$expected_repository" --arg revision "$source_revision" \
    '.version == $version and .repository == $repository and .sourceRevision == $revision and
     (.digest | test("^sha256:[0-9a-f]{64}$"))' <<<"$selected" >/dev/null || {
      echo "selected child-chart manifest does not match pinned $name:$version" >&2; exit 1;
    }
  for ((attempt=1; attempt<=wait_attempts; attempt++)); do
    if chart="$(helm show chart "$expected_repository:$version" 2>/dev/null)" && \
       descriptor="$(oras manifest fetch --descriptor "${expected_repository#oci://}:$version" 2>/dev/null)"; then
      actual_digest="$(jq -er '.digest' <<<"$descriptor")"
      grep -Fxq "name: $name" <<<"$chart" || { echo "unexpected chart name for $name:$version" >&2; exit 1; }
      grep -Fxq "version: $version" <<<"$chart" || { echo "unexpected chart version for $name:$version" >&2; exit 1; }
      [[ "$actual_digest" == "$expected_digest" ]] || {
        echo "published child chart digest does not match selected immutable artifact: $expected_repository:$version" >&2
        exit 1
      }
      jq -cn --arg repository "$expected_repository" --arg version "$version" \
        --arg digest "$expected_digest" --arg sourceRevision "$source_revision" \
        '{repository:$repository,version:$version,digest:$digest,sourceRevision:$sourceRevision}'
      return 0
    fi
    if (( attempt < wait_attempts )); then
      echo "waiting for $name chart $version (attempt $attempt/$wait_attempts)" >&2
      sleep "$wait_seconds"
    fi
  done
  echo "required child chart was not published before compatibility resolution: $name:$version; run Publish selected stable child charts" >&2
  return 1
}

latest_published_umbrella() {
  local candidate="$1" major minor patch next found=false
  IFS=. read -r major minor patch <<< "$candidate"
  for _ in $(seq 1 50); do
    candidate="$major.$minor.$patch"
    if helm show chart "oci://ghcr.io/$owner/envpilot:$candidate" >/dev/null 2>&1; then found=true; break; fi
    (( patch > 0 )) || break
    patch=$((patch - 1))
  done
  [[ "$found" == true ]] || { echo "no published umbrella chart found near $1" >&2; exit 1; }
  for _ in $(seq 1 50); do
    next="$major.$minor.$((patch + 1))"
    if helm show chart "oci://ghcr.io/$owner/envpilot:$next" >/dev/null 2>&1; then patch=$((patch + 1)); else break; fi
  done
  printf '%s.%s.%s' "$major" "$minor" "$patch"
}

source_revision="${GITHUB_SHA:-}"
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || source_revision="$(git -C "$(dirname "$chart_file")/../.." rev-parse HEAD 2>/dev/null || true)"
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { echo "source revision is unavailable" >&2; exit 1; }
umbrella_version="$(awk '/^version:/{print $2; exit}' "$chart_file")"
previous_umbrella="$(latest_published_umbrella "$umbrella_version")"
images="$(jq -cn \
  --argjson controlPlane "$(image_json envpilot-control-plane control-plane)" \
  --argjson frontend "$(image_json envpilot-frontend frontend)" \
  --argjson agent "$(image_json envpilot-agent agent)" \
  --argjson runner "$(image_json envpilot-runner runner)" \
  --argjson platformReconciler "$(image_json platformDependencyReconciler platform-reconciler)" \
  '{controlPlane:$controlPlane,frontend:$frontend,agent:$agent,runner:$runner,platformReconciler:$platformReconciler}')"
control_plane_chart="$(chart_json envpilot-control-plane envpilot-control-plane)"
frontend_chart="$(chart_json envpilot-frontend envpilot-frontend)"
agent_chart="$(chart_json envpilot-agent envpilot-agent)"
runner_chart="$(chart_json envpilot-runner envpilot-runner)"
charts="$(jq -cn \
  --argjson controlPlane "$control_plane_chart" \
  --argjson frontend "$frontend_chart" \
  --argjson agent "$agent_chart" \
  --argjson runner "$runner_chart" \
  '{controlPlane:$controlPlane,frontend:$frontend,agent:$agent,runner:$runner}')"

mkdir -p "$(dirname "$output")"
jq -n --arg previousUmbrellaVersion "$previous_umbrella" \
  --arg sourceRevision "$source_revision" \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson images "$images" --argjson charts "$charts" \
  '{schemaVersion:1,generatedAt:$generatedAt,sourceRevision:$sourceRevision,previousUmbrellaVersion:$previousUmbrellaVersion,images:$images,charts:$charts}' \
  > "$output"
echo "resolved pinned published artifacts: $output"
