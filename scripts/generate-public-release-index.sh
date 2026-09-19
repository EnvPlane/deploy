#!/usr/bin/env bash
set -euo pipefail

version=""
digest=""
source_revision=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --digest) digest="${2:-}"; shift 2 ;;
    --source-revision) source_revision="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "stable SemVer is required" >&2; exit 2; }
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "immutable chart digest is required" >&2; exit 2; }
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { echo "source revision is required" >&2; exit 2; }
[[ -n "$output" ]] || { echo "output path is required" >&2; exit 2; }

jq -n \
  --arg version "$version" \
  --arg digest "$digest" \
  --arg sourceRevision "$source_revision" \
  --arg installCommand "helm upgrade --install envplane oci://ghcr.io/envplane/envplane --version $version --namespace envplane --create-namespace --wait" \
  '{
    schemaVersion: 1,
    channel: "stable",
    version: $version,
    sourceRevision: $sourceRevision,
    chart: {repository: "oci://ghcr.io/envplane/envplane", digest: $digest},
    support: {
      kubernetes: {minimum: "1.26.0"},
      helm: {minimum: "3.14.0"},
      deploymentModes: ["cloud", "on-prem"],
      clusterTargets: ["current", "remote"]
    },
    install: {
      release: "envplane",
      namespace: "envplane",
      command: $installCommand,
      prerequisites: ["kubernetes", "helm", "default-storage-class", "namespace-rbac", "public-oci-egress"]
    },
    status: {commands: [
      "kubectl -n envplane rollout status deployment/envplane-control-plane --timeout=10m",
      "kubectl -n envplane rollout status deployment/envplane-frontend --timeout=10m",
      "kubectl -n envplane port-forward svc/envplane-frontend 3000:3000"
    ]},
    firstRun: {url: "http://127.0.0.1:3000", screen: "initial-authentication"}
  }' > "$output"

jq -e '
  .version as $version |
  .schemaVersion == 1 and .channel == "stable" and
  (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.sourceRevision | test("^[0-9a-f]{40}$")) and
  (.chart.digest | test("^sha256:[0-9a-f]{64}$")) and
  (.install.command | contains(" --version " + $version + " ")) and
  ([paths(scalars) as $p | getpath($p) | strings] | join(" ") | test("kubeconfig|credential|token"; "i") | not)
' "$output" >/dev/null
