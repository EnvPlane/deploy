#!/usr/bin/env bash
set -euo pipefail
version=""; source_revision="${GITHUB_SHA:-}"; values_file="deploy/helm/envpilot/values.yaml"; chart_file="deploy/helm/envpilot/Chart.yaml"; artifact_report=""; output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --source-revision) source_revision="${2:-}"; shift 2 ;;
    --values-file) values_file="${2:-}"; shift 2 ;;
    --chart-file) chart_file="${2:-}"; shift 2 ;;
    --artifact-report) artifact_report="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "umbrella version must be SemVer X.Y.Z" >&2; exit 2; }
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { echo "source revision must be a full SHA" >&2; exit 2; }
[[ -n "$output" ]] || { echo "--output is required" >&2; exit 2; }
if [[ -n "$artifact_report" ]]; then
  [[ -f "$artifact_report" ]] || { echo "artifact report not found: $artifact_report" >&2; exit 2; }
  jq -e --arg revision "$source_revision" \
    '.schemaVersion == 1 and .sourceRevision == $revision and (.charts | length == 5)' "$artifact_report" >/dev/null || {
    echo "artifact report does not contain five selected child charts" >&2; exit 1;
  }
fi
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
  local name="$1" chart_repo="$2" report_key="$3" v selected
  v="$(awk -v n="$name" '$0=="  - name: " n {in_d=1} in_d&&$0~/^    version:/{print $2; exit} in_d&&$0~/^  - name:/&&$0!="  - name: " n{exit}' "$chart_file")"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid child chart version for $name" >&2; exit 1; }
  if [[ -z "$artifact_report" ]]; then
    jq -cn --arg name "$name" --arg version "$v" --arg repository "$chart_repo" '{name:$name,version:$version,repository:$repository}'
    return 0
  fi
  selected="$(jq -cer --arg key "$report_key" '.charts[$key]' "$artifact_report")"
  jq -e --arg version "$v" --arg repository "$chart_repo" \
    '.version == $version and .repository == $repository and
     (.digest | test("^sha256:[0-9a-f]{64}$")) and
     (.sourceRevision | test("^[0-9a-f]{40}$"))' <<<"$selected" >/dev/null || {
      echo "artifact report child chart does not match $name:$v" >&2; exit 1;
    }
  jq -cn --arg name "$name" --arg version "$v" --arg repository "$chart_repo" \
    --arg digest "$(jq -er '.digest' <<<"$selected")" \
    --arg sourceRevision "$(jq -er '.sourceRevision' <<<"$selected")" \
    '{name:$name,version:$version,repository:$repository,digest:$digest,sourceRevision:$sourceRevision}'
}
images="$(printf '%s\n' "$(image_json envpilot-control-plane control-plane)" "$(image_json envpilot-frontend frontend)" "$(image_json envpilot-agent agent)" "$(image_json envpilot-runner runner)" "$(image_json envpilot-webhook webhook)" "$(image_json platformDependencyReconciler platform-reconciler)" | jq -s .)"
charts="$(printf '%s\n' "$(dep_json envpilot-control-plane oci://ghcr.io/envpilot/envpilot-control-plane controlPlane)" "$(dep_json envpilot-frontend oci://ghcr.io/envpilot/envpilot-frontend frontend)" "$(dep_json envpilot-agent oci://ghcr.io/envpilot/envpilot-agent agent)" "$(dep_json envpilot-runner oci://ghcr.io/envpilot/envpilot-runner runner)" "$(dep_json envpilot-webhook oci://ghcr.io/envpilot/envpilot-webhook webhook)" | jq -s .)"
[[ "$(jq 'length' <<<"$images")" == 6 ]] || { echo "compatibility manifest requires six immutable images" >&2; exit 1; }
[[ "$(jq 'length' <<<"$charts")" == 5 ]] || { echo "compatibility manifest requires five child charts" >&2; exit 1; }
if [[ -n "$artifact_report" ]]; then
  jq -e 'all(.[]; (.digest | test("^sha256:[0-9a-f]{64}$")) and (.sourceRevision | test("^[0-9a-f]{40}$")))' <<<"$charts" >/dev/null || {
    echo "compatibility manifest requires immutable child chart digests" >&2; exit 1;
  }
fi
mkdir -p "$(dirname "$output")"
jq -n --arg version "$version" --arg sourceRevision "$source_revision" --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson images "$images" --argjson charts "$charts" '{schemaVersion:1,umbrella:{name:"envpilot",version:$version},sourceRevision:$sourceRevision,generatedAt:$generatedAt,images:$images,childCharts:$charts}' > "$output"
echo "generated compatibility manifest: $output"
