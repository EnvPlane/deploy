#!/usr/bin/env bash
# Pull a signed release from CI. This program only operates on the dedicated
# local Kind cluster; GitHub Actions never receives a kubeconfig.
set -euo pipefail
umask 077
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

state="$HOME/.local/state/envplane-ci-test"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
context=kind-envplane-ci-test
target=(--kubeconfig "$state/kubeconfig" --kube-context "$context" --namespace envplane)
signer="https://github.com/""Env""Plane/deploy/.github/workflows/release-on-main.yaml@refs/heads/main"
repository=oci://ghcr.io/envplane/envplane
export HELM_REGISTRY_CONFIG="$state/registry.json"

[[ -f "$state/kubeconfig" ]] || { echo "Dedicated kubeconfig missing" >&2; exit 1; }
[[ "$(kubectl --kubeconfig "$state/kubeconfig" config get-contexts -o name)" == "$context" ]]
[[ "$(kubectl --kubeconfig "$state/kubeconfig" config view -o json | jq -er '.clusters | if length == 1 then .[0].cluster.server else empty end')" =~ ^https://127\.0\.0\.1:[0-9]+$ ]]

lock="$state/reconcile.lock"
mkdir "$lock" || { echo "Reconcile already locked; inspect before clearing" >&2; exit 1; }
scratch=""
cleanup() {
  if [[ -n "$scratch" ]]; then
    rm -f "$scratch/index.json" "$scratch/bundle.json" "$scratch/envplane-${version:-}.tgz"
    rmdir "$scratch" || true
  fi
  rmdir "$lock"
}
trap cleanup EXIT
scratch="$(mktemp -d "$state/reconcile.XXXXXX")"

tag="$(gh release view -R EnvPlane/deploy --json tagName,isDraft,isPrerelease --jq 'select(.isDraft == false and .isPrerelease == false) | .tagName')"
[[ "$tag" =~ ^envplane-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
version="${tag#envplane-v}"
installed="$(helm list "${target[@]}" --filter '^envplane$' -o json | jq -er 'if length == 0 then "" elif length == 1 and .[0].status == "deployed" then .[0].chart | sub("^envplane-";"") else error("Unhealthy release; inspect manually") end')"
if [[ -n "$installed" ]]; then
  [[ "$installed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  if [[ "$installed" == "$version" ]]; then exit 0; fi
  newer="$(printf '%s\n' "$installed" "$version" | LC_ALL=C sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
  [[ "$newer" == "$version" ]] || { echo "Refusing to downgrade $installed to $version" >&2; exit 1; }
fi
gh release download "$tag" -R EnvPlane/deploy --pattern "envplane-$version-release-index.json" --output "$scratch/index.json"
gh release download "$tag" -R EnvPlane/deploy --pattern "envplane-$version-release-index.sigstore.json" --output "$scratch/bundle.json"
cosign verify-blob --bundle "$scratch/bundle.json" --certificate-identity "$signer" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com "$scratch/index.json"
expected="$(jq -er --arg version "$version" --arg repo "$repository" '
  select(.schemaVersion == 1 and .channel == "stable" and .version == $version and .chart.repository == $repo)
  | .chart.digest | select(test("^sha256:[0-9a-f]{64}$"))
' "$scratch/index.json")"
pull="$(helm pull "$repository" --version "$version" --destination "$scratch" 2>&1)"
actual="$(printf '%s\n' "$pull" | sed -n 's/^Digest: //p')"
[[ "$actual" == "$expected" ]] || { echo "OCI digest mismatch" >&2; exit 1; }

blocked="$state/blocked-$version"
[[ ! -e "$blocked" ]] || { echo "Release $version previously failed; inspect before retrying" >&2; exit 1; }
if ! helm upgrade --install envplane "$scratch/envplane-$version.tgz" "${target[@]}" \
  --create-namespace --values "$root/deploy/helm/envplane/values-e2e-local.yaml" --set access.mode=disabled \
  --set webhook.enabled=false --set envplane-frontend.service.type=ClusterIP \
  --set envplane-control-plane.service.type=ClusterIP \
  --set 'envplane-control-plane.commercialization.issuerConnection.enabled=false' \
  --set-string envplane-control-plane.commercialization.billing.provider=,envplane-control-plane.commercialization.billing.baseURL= \
  --set-string envplane-control-plane.commercialization.license.activationIssuerURL= \
  --wait --rollback-on-failure --timeout 12m; then
  touch "$blocked"
  exit 1
fi
echo "Verified and installed $tag ($expected) in $context"
