#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$root/.github/workflows/release-on-main.yaml"
artifact_workflow="$root/.github/workflows/publish-main.yaml"
resolver="$root/scripts/resolve-latest-published-artifacts.sh"
child_publisher="$root/scripts/publish-selected-child-charts.sh"
freshness_gate="$root/scripts/ensure-current-compatible-artifact.sh"
frontend_smoke="$root/scripts/verify-frontend-component-repair-controls.sh"
secret_lifecycle_harness="$root/scripts/private-registry-secret-materialization-e2e.sh"
anonymous_oci_harness="$root/scripts/verify-anonymous-oci-artifacts.sh"
runtime_receiver="$root/.github/workflows/propose-runtime-image-update.yaml"
chart_receiver="$root/.github/workflows/propose-umbrella-chart-dependency-update.yaml"

[[ -f "$workflow" ]] || { echo "main release workflow is missing" >&2; exit 1; }
[[ -x "$resolver" ]] || { echo "artifact resolver is not executable" >&2; exit 1; }
[[ -x "$child_publisher" ]] || { echo "selected child-chart publisher is not executable" >&2; exit 1; }
[[ -x "$freshness_gate" ]] || { echo "compatibility freshness gate is not executable" >&2; exit 1; }
[[ -x "$frontend_smoke" ]] || { echo "frontend image smoke check is not executable" >&2; exit 1; }
[[ -x "$secret_lifecycle_harness" ]] || { echo "private-registry lifecycle harness must be executable" >&2; exit 1; }
[[ -x "$anonymous_oci_harness" ]] || { echo "anonymous OCI harness must be executable" >&2; exit 1; }
bash -n "$resolver"
bash -n "$child_publisher"
bash -n "$freshness_gate"
bash -n "$frontend_smoke"
bash -n "$secret_lifecycle_harness"
bash -n "$anonymous_oci_harness"

for required in \
  "workflow_run:" \
  "Publish deploy image and charts (main)" \
  "workflow_run.conclusion" \
  "actions/download-artifact@v8" \
  "envplane-compatible-artifacts" \
  "artifact_run_id" \
  "oras-project/setup-oras@v2" \
  "oras login ghcr.io" \
  "helm dependency build" \
  "Run Secret materialization executor lifecycle gate" \
  "release-gate-agent" \
  "helm package" \
  "helm push" \
  "cosign attest" \
  "Verify anonymous OCI pulls for the complete release" \
  "gh release create" \
  "Update stable installation documentation" \
  "render-install-docs-from-release-index.sh" \
  'git -C "$docs_tree" push origin HEAD:refs/heads/main'; do
  grep -Fq "$required" "$workflow" || { echo "workflow missing: $required" >&2; exit 1; }
done

grep -Fq 'verify-anonymous-oci-artifacts.sh' "$workflow" || {
  echo "release must verify anonymous OCI pulls after publication" >&2; exit 1;
}

for signed_index_contract in \
  'generate-public-release-index.sh' \
  'cosign sign-blob --yes' \
  'release-index.json' \
  'release-index.sigstore.json'; do
  grep -Fq "$signed_index_contract" "$workflow" || {
    echo "release workflow is missing signed public index contract: $signed_index_contract" >&2
    exit 1
  }
done

grep -Fq 'docker pull --platform' "$anonymous_oci_harness" || {
  echo "anonymous OCI harness must pull both image architectures" >&2; exit 1;
}

grep -Fq 'docker image rm --force' "$anonymous_oci_harness" || {
  echo "anonymous OCI harness must isolate platform pulls in the local image store" >&2; exit 1;
}

grep -Fq 'helm pull oci://ghcr.io/envplane/envplane' "$anonymous_oci_harness" || {
  echo "anonymous OCI harness must pull the umbrella without login" >&2; exit 1;
}

if grep -Eq '^  push:' "$workflow"; then
  echo "umbrella release must not run directly on push" >&2
  exit 1
fi

grep -Fq "github.repository == 'EnvPlane/deploy'" "$workflow" || {
  echo "umbrella release must target the canonical EnvPlane deploy repository" >&2
  exit 1
}

if grep -Fq "github.repository == 'envplane/deploy'" "$workflow"; then
  echo "umbrella release must not retain the retired repository gate" >&2
  exit 1
fi

grep -Fq "pinned source tree" "$resolver" || {
  echo "resolver must verify pinned source artifacts rather than selecting registry latest" >&2
  exit 1
}

grep -Fq -- "--values-file" "$artifact_workflow" || {
  echo "artifact workflow must resolve the image refs committed in values.yaml" >&2
  exit 1
}

grep -Fq 'Publish selected stable child charts' "$artifact_workflow" || {
  echo "artifact workflow must publish selected stable child charts before resolution" >&2
  exit 1
}

grep -Fq 'publish-selected-child-charts.sh' "$artifact_workflow" || {
  echo "artifact workflow must use the canonical child-chart publisher" >&2
  exit 1
}

grep -Fq -- "--owner 'envplane'" "$artifact_workflow" || {
  echo "artifact workflow must preserve the canonical lowercase EnvPlane OCI namespace" >&2
  exit 1
}

if grep -B2 -F -- "--owner 'EnvPlane'" "$artifact_workflow" | grep -Eq '^            #'; then
  echo "workflow comments must not interrupt the continued child-chart publisher command" >&2
  exit 1
fi

if grep -Fq -- '--owner '\''${{ github.repository_owner }}'\''' "$artifact_workflow"; then
  echo "artifact workflow must not derive OCI namespace from GitHub repository owner casing" >&2
  exit 1
fi

grep -Fq -- '--selected-child-charts' "$artifact_workflow" || {
  echo "artifact workflow must pass the selected child-chart manifest to the resolver" >&2
  exit 1
}

if grep -Fq -- '-main.${GITHUB_RUN_NUMBER}' "$artifact_workflow"; then
  echo "artifact workflow must not substitute -main prereleases for stable child dependencies" >&2
  exit 1
fi

grep -Fq "waiting for" "$resolver" || {
  echo "resolver must wait for a pinned artifact still being published" >&2
  exit 1
}

grep -Fq 'run Publish selected stable child charts first' "$resolver" || {
  echo "resolver must provide an actionable missing child-chart diagnostic" >&2
  exit 1
}

grep -Fq 'published child chart digest does not match selected immutable artifact' "$resolver" || {
  echo "resolver must verify selected child-chart digests" >&2
  exit 1
}

grep -Fq 'sourceRevision:$sourceRevision' "$resolver" || {
  echo "artifact resolver must bind the report to the source revision" >&2
  exit 1
}

grep -Fq 'Select the artifact source revision' "$workflow" || {
  echo "release must checkout the artifact workflow source revision" >&2
  exit 1
}

grep -Fq 'Ensure selected compatibility set is current deploy main' "$workflow" || {
  echo "release must reject a compatibility report superseded on deploy/main" >&2
  exit 1
}

grep -Fq 'ensure-current-compatible-artifact.sh' "$workflow" || {
  echo "release must enforce current-main compatibility selection" >&2
  exit 1
}

grep -Fq 'git ls-remote origin refs/heads/main' "$workflow" || {
  echo "release must compare the artifact revision with deploy/main" >&2
  exit 1
}

for receiver in "$runtime_receiver" "$chart_receiver"; do
  grep -Fq 'gh pr merge "$PR_NUMBER" --squash --delete-branch --repo EnvPlane/deploy' "$receiver" || {
    echo "published component pins must merge after their validated update" >&2
    exit 1
  }
  if grep -Fq 'enablePullRequestAutoMerge' "$receiver"; then
    echo "published component pins must not silently remain pending when auto-merge is disabled" >&2
    exit 1
  fi
done

grep -Fq 'Verify confirmed immutable artifacts' "$workflow" || {
  echo "release must validate the downloaded compatibility manifest" >&2
  exit 1
}

grep -Fq '.images.agent.sourceRevision' "$workflow" || {
  echo "release must test the Agent revision selected by the compatibility report" >&2
  exit 1
}

grep -Fq "TestSecretMaterializationReleaseGate" "$workflow" || {
  echo "release must run the required Secret materialization lifecycle test" >&2
  exit 1
}

grep -Fq "Run disposable private-registry Secret materialization release gate" "$workflow" || {
  echo "release must run the mandatory clean-cluster private-registry Secret lifecycle gate" >&2
  exit 1
}
grep -A2 -F 'uses: azure/setup-helm@v5' "$workflow" | grep -Fq 'version: v3.21.3' || {
  echo "release workflow must pin the supported Helm 3 client" >&2
  exit 1
}

grep -Fq -- '--values "$base_values" --values "$values"' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must layer its SM-09 values over the canonical E2E profile" >&2
  exit 1
}

if grep -Fq 'create namespace "$base_namespace"' "$secret_lifecycle_harness" ||
   grep -Fq 'create namespace "$target_namespace"' "$secret_lifecycle_harness"; then
  echo "private-registry lifecycle harness must let the umbrella release own fixture namespaces" >&2
  exit 1
fi

for namespace_binding in \
  'namespace: $namespace' \
  'namespaces: [$base_namespace]' \
  'namespaces: [$target_namespace]' \
  'envplane-control-plane.$namespace.svc'; do
  grep -Fq "$namespace_binding" "$secret_lifecycle_harness" || {
    echo "private-registry lifecycle harness is missing namespace binding: $namespace_binding" >&2
    exit 1
  }
done

if grep -Eq 'docker_config|imagePullSecrets:' "$secret_lifecycle_harness" ||
  grep -Eq 'create secret .*release-registry-pull' "$secret_lifecycle_harness"; then
  echo "private-registry lifecycle harness must install public runtime artifacts without hidden GHCR image-pull credentials" >&2
  exit 1
fi

grep -Fq 'create secret docker-registry registry-source' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must retain the disposable source Secret used by encrypted-clone coverage" >&2
  exit 1
}

grep -Fq 'SM-09 runtime Deployments must pull public artifacts without imagePullSecrets' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must assert that platform Deployments do not use imagePullSecrets" >&2
  exit 1
}

grep -Fq 'SM-09 Agent preflight diagnostics' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must emit redacted Agent preflight diagnostics" >&2
  exit 1
}

grep -Fq "curl --noproxy '*' --silent --show-error" "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must bypass ambient proxies and explicitly inspect local API responses" >&2
  exit 1
}

grep -Fq 'ENVPLANE_API_WRITE_TOKEN: $api_token' "$secret_lifecycle_harness" &&
  grep -Fq 'Authorization: Bearer $api_token' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must use its disposable authenticated API client" >&2
  exit 1
}

grep -Fq 'SM-09 API request failed:' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must emit redacted Bootstrap API diagnostics" >&2
  exit 1
}
grep -Fq 'api-response.XXXXXX' "$secret_lifecycle_harness" &&
  grep -Fq 'non_json_http_response' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must retain redacted evidence for failed API reads" >&2
  exit 1
}
grep -Fq 'SM-11 clean-install environment did not reach Ready with a URL' "$secret_lifecycle_harness" &&
  grep -Fq '(.status == "ready" or .status == "running")' "$secret_lifecycle_harness" &&
  grep -Fq 'environment_release="$project-$environment"' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must prove a clean-install environment reaches Ready with a URL" >&2
  exit 1
}
grep -Fq 'ENVPLANE_SM09_FIRST_RUN_BROWSER_GATE' "$secret_lifecycle_harness" &&
  grep -Fq 'npm run test:e2e:real' "$secret_lifecycle_harness" &&
  grep -Fq 'ENVPLANE_E2E_RUN_LIFECYCLE=1' "$secret_lifecycle_harness" &&
  grep -Fq 'ENVPLANE_E2E_FIRST_RUN_SETUP_TOKEN="$setup_token"' "$secret_lifecycle_harness" &&
  grep -Fq 'ENVPLANE_E2E_FIRST_RUN_ACTIVATION_CODE="$activation_code"' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must execute the live first-run browser gate with in-memory credentials" >&2
  exit 1
}
grep -Fq 'cmd/e2e-activation-fixture sign' "$secret_lifecycle_harness" &&
  grep -Fq 'activationPublicKeysJSON:' "$secret_lifecycle_harness" &&
  grep -Fq 'graceDays: 0' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must use an ephemeral public-key-bound activation fixture" >&2
  exit 1
}
grep -Fq 'repository: EnvPlane/frontend' "$workflow" &&
  grep -Fq 'Select compatible source checkout authentication' "$workflow" &&
  grep -Fq 'token: ${{ steps.source_read_app.outputs.token || secrets.ENVPLANE_AUTOMATION_PAT }}' "$workflow" &&
  grep -Fq 'ENVPLANE_SM09_FIRST_RUN_BROWSER_GATE: "1"' "$workflow" &&
  grep -Fq 'ENVPLANE_SM09_FRONTEND_DIR: ${{ github.workspace }}/release-gate-frontend' "$workflow" &&
  grep -Fq 'playwright install --with-deps chromium' "$workflow" || {
  echo "umbrella publication must require the compatible frontend live browser gate" >&2
  exit 1
}
grep -Fq '.resourceScanStatus == "completed"' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must wait for the Agent resource scan before compilation" >&2
  exit 1
}
grep -Fq 'deployment\":{\"backend\":\"helm_direct' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must persist the Helm Direct deployment contract before compilation" >&2
  exit 1
}
if grep -Eq '^envplane-(frontend|webhook):[[:space:]]*$' "$secret_lifecycle_harness"; then
  echo "private-registry lifecycle harness must not erase signed component image pins with empty values" >&2
  exit 1
fi
grep -Fq '/bootstrap-session/helm-direct/preflight' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must exercise Runner Helm chart preflight before compilation" >&2
  exit 1
}
grep -Fq '.data.helmDirectChartValidation | .status == "succeeded"' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must wait for the matching Runner chart validation" >&2
  exit 1
}
grep -Fq -- "-w '%{http_code}'" "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must preserve Bootstrap API error responses" >&2
  exit 1
}
grep -Fq '\"project\":\"$project\"' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must bind the canonical environment project field" >&2
  exit 1
}
grep -Fq '\"clusterId\":\"local-e2e\"' "$secret_lifecycle_harness" || {
  echo "private-registry lifecycle harness must bind the canonical environment cluster field" >&2
  exit 1
}
if grep -Fq '\"project_id\":\"$project\"' "$secret_lifecycle_harness" || grep -Fq '\"cluster_id\":\"local-e2e\"' "$secret_lifecycle_harness"; then
  echo "private-registry lifecycle harness must not use unsupported environment request aliases" >&2
  exit 1
fi

grep -Fq 'minimum="0.4.0"' "$workflow" || {
  echo "release must start the EnvPlane umbrella line at 0.4.0" >&2
  exit 1
}

grep -Fq 'Smoke-check editable Draft component controls in frontend image' "$workflow" || {
  echo "release must smoke-check the frontend image before packaging the umbrella" >&2
  exit 1
}

grep -Fq 'verify-frontend-component-repair-controls.sh' "$workflow" || {
  echo "release must verify editable component controls in the pinned frontend digest" >&2
  exit 1
}

if grep -Fq 'Resolve latest published immutable artifacts' "$workflow"; then
  echo "release must consume the confirmed artifact manifest, not resolve independently" >&2
  exit 1
fi

grep -Fq 'controlPlane:control-plane' "$workflow" || {
  echo "workflow must map report controlPlane to the control-plane values component" >&2
  exit 1
}

grep -Fq 'e2eWorkload:e2e-workload' "$workflow" || {
  echo "workflow must publish and pin the Helm Direct bootstrap workload with the umbrella" >&2
  exit 1
}

grep -Fq '.charts[$component].version' "$workflow" || {
  echo "workflow must read child chart versions from the compatibility report" >&2
  exit 1
}

grep -Fq -- '--artifact-report "$REPORT"' "$workflow" || {
  echo "release compatibility manifest must retain confirmed child-chart digests" >&2
  exit 1
}

grep -Fq 'latest_published_umbrella' "$resolver" || {
  echo "resolver must verify the predecessor umbrella exists in OCI" >&2
  exit 1
}

if grep -Fq 'latest_image_tag' "$resolver" || grep -Fq 'package_versions' "$resolver"; then
  echo "resolver must not scan GHCR and select an unrelated latest image" >&2
  exit 1
fi

for required in \
  "ghcr.io/envplane/api" \
  "ghcr.io/envplane/frontend" \
  "ghcr.io/envplane/agent" \
  "ghcr.io/envplane/runner" \
  "ghcr.io/envplane/webhook" \
  "ghcr.io/envplane/platform-reconciler"; do
  grep -Fq "$required" "$root/deploy/helm/envplane/values.yaml" || { echo "pinned values missing: $required" >&2; exit 1; }
done

if grep -Eq ':[[:space:]]*(latest|main)([[:space:]"'"'"'@]|$)|tag:[[:space:]]*(latest|main)([[:space:]"'"'"'@]|$)' "$workflow"; then
  echo "automatic umbrella releases must not use mutable latest/main refs" >&2
  exit 1
fi

echo "release-on-main workflow contract is valid"
