#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--report" || "${1:-}" == "--candidate" ]]; then
  exec python3 "$script_dir/validate-component-ci.py" "$@"
fi
manifest="${1:-deploy/release/0.3.0.yaml}"
[[ -f "$manifest" ]] || { echo "release manifest not found" >&2; exit 2; }
for artifact in contracts controlPlane frontend agent runner webhook gitops bootstrap deploy; do
  grep -Eq "^  ${artifact}:" "$manifest" || { echo "missing tested artifact: $artifact" >&2; exit 1; }
  grep -Eq "^  ${artifact}:.*version: \"[0-9]+\.[0-9]+\.[0-9]+\".*artifactDigest: \"sha256:[0-9a-f]{64}\"" "$manifest" || { echo "missing immutable artifact pin: $artifact" >&2; exit 1; }
done
grep -Eq 'requiredFlow: \[multi_namespace_scan, immutable_template, scm_mr_open, independent_feature, update, close_cleanup\]' "$manifest" || exit 1
grep -Eq 'reject: \[placeholder, stale_artifact, credential_payload, contract_skew\]' "$manifest" || exit 1
if grep -Eiq 'password:|access_token:|refresh_token:|private_key:|client_secret:' "$manifest"; then exit 1; fi
while read -r revision; do [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid tested artifact revision" >&2; exit 1; }; done < <(grep 'sourceRevision:' "$manifest" | sed -E 's/.*"([0-9a-f]+)".*/\1/')
# Legacy manifest syntax remains supported, but structural acceptance is not CI.
ci_args=()
for artifact in contracts controlPlane frontend agent runner webhook gitops bootstrap deploy; do
  line="$(grep -E "^  ${artifact}:" "$manifest")"
  revision="$(sed -nE 's/.*sourceRevision: "([0-9a-f]{40})".*/\1/p' <<<"$line")"
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "missing exact tested artifact revision: $artifact" >&2; exit 1; }
  repository="$artifact"
  [[ "$artifact" != controlPlane ]] || repository=control-plane
  ci_args+=(--candidate "$repository=$revision")
done
python3 "$script_dir/validate-component-ci.py" "${ci_args[@]}"
echo "release gate manifest accepted: $manifest"
