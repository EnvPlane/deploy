#!/usr/bin/env bash
set -euo pipefail

report=""
main_revision=""
artifact_name="envplane-compatible-artifacts"
owner_repo="${GITHUB_REPOSITORY:-EnvPlane/deploy}"

echo_usage() {
  cat <<'USAGE'
Usage: resolve-compatible-manifest.sh --report <path> --main-revision <sha>
  --report           Path to compatibility report JSON (latest-artifacts.json)
  --main-revision    Expected main revision SHA
  [--artifact-name]  Artifact name to download (default envplane-compatible-artifacts)
  [--repository]     Repository in OWNER/REPO form (default GITHUB_REPOSITORY)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      report="$2"
      shift 2
      ;;
    --main-revision)
      main_revision="$2"
      shift 2
      ;;
    --artifact-name)
      artifact_name="$2"
      shift 2
      ;;
    --repository)
      owner_repo="$2"
      shift 2
      ;;
    -h|--help)
      echo_usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      echo_usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$report" ]]; then
  echo "--report is required" >&2
  exit 2
fi

if [[ -z "$main_revision" ]]; then
  echo "--main-revision is required" >&2
  exit 2
fi

if [[ ! -f "$report" ]]; then
  echo "compatibility report is missing: $report" >&2
  exit 2
fi

if [[ ! "$main_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "main revision must be a full lowercase commit SHA" >&2
  exit 2
fi

source_revision="$(jq -er '.sourceRevision // empty' "$report")"
if [[ -z "$source_revision" || ! "$source_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "compatibility report has invalid sourceRevision" >&2
  exit 2
fi

if [[ "$source_revision" == "$main_revision" ]]; then
  echo "compatibility manifest already matches deploy/main"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 2
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "unzip is required" >&2
  exit 2
fi

token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$token" ]]; then
  echo "GITHUB_TOKEN is required" >&2
  exit 2
fi

runs_json="$(mktemp)"
trap 'rm -f "$runs_json"' EXIT

runs_url="https://api.github.com/repos/$owner_repo/actions/workflows/publish-main.yaml/runs?status=completed&conclusion=success&per_page=40"
curl -fsSL -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$runs_url" > "$runs_json"

run_id="$(jq -r --arg rev "$main_revision" '.workflow_runs[] | select(.head_sha == $rev) | .id' "$runs_json" | head -n 1)"
if [[ -z "$run_id" || "$run_id" == "null" ]]; then
  echo "compatibility manifest for main revision $main_revision was not found in a successful publish run" >&2
  exit 1
fi

echo "selected publish-main run $run_id for main revision $main_revision"

artifacts_json="$(mktemp)"
trap 'rm -f "$runs_json" "$artifacts_json"' EXIT
artifact_url="https://api.github.com/repos/$owner_repo/actions/runs/$run_id/artifacts?per_page=100"
curl -fsSL -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$artifact_url" > "$artifacts_json"

artifact_id="$(jq -r --arg name "$artifact_name" '.artifacts[] | select(.name == $name and (.expired == false)) | .id' "$artifacts_json" | head -n 1)"
if [[ -z "$artifact_id" || "$artifact_id" == "null" ]]; then
  echo "artifact '$artifact_name' not found in publish run $run_id" >&2
  exit 1
fi

tmp_archive="$(mktemp)"
tmp_extract_dir="$(mktemp -d)"
trap 'rm -f "$runs_json" "$artifacts_json" "$tmp_archive"; rm -rf "$tmp_extract_dir"' EXIT
artifact_download_url="https://api.github.com/repos/$owner_repo/actions/artifacts/$artifact_id/zip"
curl -fsSL -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$artifact_download_url" -o "$tmp_archive"
unzip -q -o "$tmp_archive" -d "$tmp_extract_dir"
manifest_file="$(find "$tmp_extract_dir" -name latest-artifacts.json -print -quit || true)"
if [[ -z "$manifest_file" ]]; then
  echo "compatibility manifest was not present in downloaded artifact" >&2
  exit 1
fi

cp "$manifest_file" "$report"
new_revision="$(jq -er '.sourceRevision // empty' "$report")"
if [[ "$new_revision" != "$main_revision" ]]; then
  echo "downloaded compatibility manifest revision mismatch: expected $main_revision got ${new_revision:-<missing>}" >&2
  exit 1
fi

echo "refreshed compatibility manifest to current deploy main revision $main_revision"
