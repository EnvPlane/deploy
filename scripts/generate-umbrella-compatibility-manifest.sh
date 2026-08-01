#!/usr/bin/env bash
set -euo pipefail
version=""; source_revision="${GITHUB_SHA:-}"; values_file="deploy/helm/envpilot/values.yaml"; chart_file="deploy/helm/envpilot/Chart.yaml"; output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --source-revision) source_revision="${2:-}"; shift 2 ;;
    --values-file) values_file="${2:-}"; shift 2 ;;
    --chart-file) chart_file="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "umbrella version must be SemVer X.Y.Z" >&2; exit 2; }
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { echo "source revision must be a full SHA" >&2; exit 2; }
[[ -n "$output" ]] || { echo "--output is required" >&2; exit 2; }
image_json() {
  local section="$1" name="$2" repository tag digest
  repository="$(awk -v s="$section" '$0==s":"{in_s=1} in_s&&$0!=s":"&&$0~/^[^[:space:]]/{exit} in_s&&$0~/^    repository:/{sub(/^    repository:[[:space:]]*/,""); print; exit}' "$values_file")"
  tag="$(awk -v s="$section" '$0==s":"{in_s=1} in_s&&$0!=s":"&&$0~/^[^[:space:]]/{exit} in_s&&$0~/^    tag:/{sub(/^    tag:[[:space:]]*/,""); gsub(/"/,""); print; exit}' "$values_file")"
  digest="$(awk -v s="$section" '$0==s":"{in_s=1} in_s&&$0!=s":"&&$0~/^[^[:space:]]/{exit} in_s&&$0~/^    digest:/{sub(/^    digest:[[:space:]]*/,""); gsub(/"/,""); print; exit}' "$values_file")"
  [[ "$tag" =~ ^sha-[0-9a-f]{40}$ ]] || { echo "mutable/missing tag for $name" >&2; exit 1; }
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "missing digest for $name" >&2; exit 1; }
  jq -cn --arg name "$name" --arg repository "$repository" --arg tag "$tag" --arg digest "$digest" '{name:$name,repository:$repository,tag:$tag,digest:$digest}'
}
dep_json() {
  local name="$1" chart_repo="$2" v
  v="$(awk -v n="$name" '$0=="  - name: " n {in_d=1} in_d&&$0~/^    version:/{print $2; exit} in_d&&$0~/^  - name:/&&$0!="  - name: " n{exit}' "$chart_file")"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid child chart version for $name" >&2; exit 1; }
  jq -cn --arg name "$name" --arg version "$v" --arg repository "$chart_repo" '{name:$name,version:$version,repository:$repository}'
}
images="$(printf '%s\n' "$(image_json envpilot-control-plane control-plane)" "$(image_json envpilot-frontend frontend)" "$(image_json envpilot-agent agent)" "$(image_json envpilot-runner runner)" | jq -s .)"
charts="$(printf '%s\n' "$(dep_json envpilot-control-plane oci://ghcr.io/envpilot/envpilot-control-plane)" "$(dep_json envpilot-frontend oci://ghcr.io/envpilot/envpilot-frontend)" "$(dep_json envpilot-agent oci://ghcr.io/envpilot/envpilot-agent)" "$(dep_json envpilot-runner oci://ghcr.io/envpilot/envpilot-runner)" | jq -s .)"
[[ "$(jq 'length' <<<"$images")" == 4 ]] || { echo "compatibility manifest requires four immutable images" >&2; exit 1; }
[[ "$(jq 'length' <<<"$charts")" == 4 ]] || { echo "compatibility manifest requires four child charts" >&2; exit 1; }
mkdir -p "$(dirname "$output")"
jq -n --arg version "$version" --arg sourceRevision "$source_revision" --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson images "$images" --argjson charts "$charts" '{schemaVersion:1,umbrella:{name:"envpilot",version:$version},sourceRevision:$sourceRevision,generatedAt:$generatedAt,images:$images,childCharts:$charts}' > "$output"
echo "generated compatibility manifest: $output"
