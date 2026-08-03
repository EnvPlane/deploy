#!/usr/bin/env bash
# Resolve the newest published, immutable EnvPilot artifacts from GHCR.
# This is intentionally read-only: the release workflow consumes the JSON
# report and updates only its ephemeral build workspace.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: resolve-latest-published-artifacts.sh --output <file> [--owner <owner>]

Requires GH_TOKEN/GITHUB_TOKEN with packages:read, Docker login for image
inspection, and Helm registry login for chart validation.
EOF
  exit 2
}

owner="envpilot"
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) owner="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$owner" =~ ^[A-Za-z0-9-]+$ ]] || { echo "invalid owner" >&2; exit 2; }
[[ -n "$output" ]] || { echo "--output is required" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
command -v helm >/dev/null || { echo "helm is required" >&2; exit 1; }
command -v oras >/dev/null || { echo "oras is required for OCI chart tag discovery" >&2; exit 1; }

package_versions() {
  local package="$1" endpoint response api_token
  api_token="${GHCR_TOKEN:-${GH_TOKEN:-}}"
  for endpoint in \
    "/users/$owner/packages/container/$package/versions?per_page=100" \
    "/orgs/$owner/packages/container/$package/versions?per_page=100"; do
    if response="$(GH_TOKEN="$api_token" gh api --paginate --slurp "$endpoint" 2>/dev/null)"; then
      jq -c 'add[]' <<< "$response"
      return 0
    fi
  done
  echo "cannot read published container package versions for $owner/$package" >&2
  return 1
}

latest_image_tag() {
  local package="$1" tag="" versions
  if versions="$(package_versions "$package" 2>/dev/null)"; then
    tag="$(jq -r 'select((.metadata.container.tags // []) | any(test("^sha-[0-9a-f]{40}$"))) | .created_at + "\t" + ((.metadata.container.tags // [])[] | select(test("^sha-[0-9a-f]{40}$")))' <<<"$versions" \
      | sort -r | head -n1 | cut -f2-)"
  fi
  # The platform reconciler is built from this deploy commit by the preceding
  # publication workflow. GitHub's user-package API may hide that package from
  # GITHUB_TOKEN, so use only the exact workflow SHA as a verified fallback.
  if [[ -z "$tag" && "$package" == platform-reconciler && "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]]; then
    tag="sha-$GITHUB_SHA"
  fi
  [[ "$tag" =~ ^sha-[0-9a-f]{40}$ ]] || {
    echo "no immutable sha-* image published for $package" >&2
    exit 1
  }
  printf '%s' "$tag"
}

image_json() {
  local package="$1" repository="$2" tag digest revision
  tag="$(latest_image_tag "$package")"
  revision="${tag#sha-}"
  digest="$(docker buildx imagetools inspect "$repository:$tag" \
    | awk '/^Digest:[[:space:]]+sha256:[0-9a-f]{64}$/ {print $2; exit}')"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "could not resolve manifest digest for $repository:$tag" >&2
    exit 1
  }
  jq -cn --arg repository "$repository" --arg tag "$tag" \
    --arg digest "$digest" --arg sourceRevision "$revision" \
    '{repository:$repository,tag:$tag,digest:$digest,sourceRevision:$sourceRevision}'
}

latest_chart_version() {
  local package="$1" version tags
  # Helm OCI charts are not exposed consistently by GitHub's package-versions
  # REST API. Discover their immutable SemVer tags from the registry itself.
  if tags="$(oras repo tags "ghcr.io/$owner/$package" 2>/dev/null)"; then
    version="$(printf '%s\n' "$tags" \
      | sed 's/^v//' \
      | grep -E '^[0-9]+\\.[0-9]+\\.[0-9]+$' \
      | sort -Vu | tail -n1 || true)"
  else
    version=""
  fi
  # A repository-owned OCI package may deny GITHUB_TOKEN registry listing even
  # when the artifact is public. Use the canonical source version in that case
  # and verify it with `helm show chart` below; a missing publication still
  # fails the release rather than silently selecting a mutable ref.
  if [[ -z "$version" ]]; then
    local source
    case "$package" in
      envpilot) source="deploy/helm/envpilot/Chart.yaml" ;;
      envpilot-control-plane) source="deploy/helm/envpilot-control-plane/Chart.yaml" ;;
      envpilot-frontend) source="deploy/helm/envpilot-frontend/Chart.yaml" ;;
      envpilot-agent) source="deploy/helm/envpilot-agent/Chart.yaml" ;;
      envpilot-runner) source="deploy/helm/envpilot-runner/Chart.yaml" ;;
      *) source="" ;;
    esac
    if [[ -n "$source" && -f "$source" ]]; then
      version="$(awk '/^version:/{print $2; exit}' "$source")"
    fi
  fi
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "no stable SemVer chart published for $package" >&2
    exit 1
  }
  printf '%s' "$version"
}

chart_json() {
  local name="$1" package="$2" repository="$3" version chart
  version="$(latest_chart_version "$package")"
  chart="$(helm show chart "$repository:$version")"
  grep -Fxq "name: $name" <<<"$chart" || {
    echo "OCI chart $repository:$version has an unexpected name" >&2
    exit 1
  }
  grep -Fxq "version: $version" <<<"$chart" || {
    echo "OCI chart $repository:$version has an unexpected version" >&2
    exit 1
  }
  jq -cn --arg repository "$repository" --arg version "$version" \
    '{repository:$repository,version:$version}'
}

latest_published_umbrella() {
  local candidate="$1" major minor patch next found=false
  IFS=. read -r major minor patch <<< "$candidate"
  # The canonical source chart may already carry the next local SemVer while
  # that version is not published yet. Walk backwards to the nearest existing
  # immutable predecessor before scanning forward for the newest contiguous
  # release. This keeps a release retry safe after a local chart bump.
  for _ in $(seq 1 50); do
    candidate="$major.$minor.$patch"
    if helm show chart "oci://ghcr.io/$owner/envpilot:$candidate" >/dev/null 2>&1; then
      found=true
      break
    fi
    (( patch > 0 )) || break
    patch=$((patch - 1))
  done
  [[ "$found" == true ]] || { echo "no published umbrella chart found near $1" >&2; exit 1; }
  for _ in $(seq 1 50); do
    next="$major.$minor.$((patch + 1))"
    if helm show chart "oci://ghcr.io/$owner/envpilot:$next" >/dev/null 2>&1; then
      patch=$((patch + 1))
    else
      break
    fi
  done
  printf '%s.%s.%s' "$major" "$minor" "$patch"
}

previous_umbrella="$(latest_published_umbrella "$(latest_chart_version "envpilot")")"
images="$(jq -cn \
  --argjson api "$(image_json api ghcr.io/envpilot/api)" \
  --argjson frontend "$(image_json frontend ghcr.io/envpilot/frontend)" \
  --argjson agent "$(image_json agent ghcr.io/envpilot/agent)" \
  --argjson runner "$(image_json runner ghcr.io/envpilot/runner)" \
  --argjson platformReconciler "$(image_json platform-reconciler ghcr.io/envpilot/platform-reconciler)" \
  '{controlPlane:$api,frontend:$frontend,agent:$agent,runner:$runner,platformReconciler:$platformReconciler}')"
charts="$(jq -cn \
  --argjson controlPlane "$(chart_json envpilot-control-plane envpilot-control-plane oci://ghcr.io/envpilot/envpilot-control-plane)" \
  --argjson frontend "$(chart_json envpilot-frontend envpilot-frontend oci://ghcr.io/envpilot/envpilot-frontend)" \
  --argjson agent "$(chart_json envpilot-agent envpilot-agent oci://ghcr.io/envpilot/envpilot-agent)" \
  --argjson runner "$(chart_json envpilot-runner envpilot-runner oci://ghcr.io/envpilot/envpilot-runner)" \
  '{controlPlane:$controlPlane,frontend:$frontend,agent:$agent,runner:$runner}')"

mkdir -p "$(dirname "$output")"
jq -n --arg previousUmbrellaVersion "$previous_umbrella" \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson images "$images" --argjson charts "$charts" \
  '{schemaVersion:1,generatedAt:$generatedAt,previousUmbrellaVersion:$previousUmbrellaVersion,images:$images,charts:$charts}' \
  > "$output"
echo "resolved latest published artifacts: $output"
