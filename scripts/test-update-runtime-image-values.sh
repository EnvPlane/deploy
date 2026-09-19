#!/usr/bin/env bash
set -euo pipefail

# Contract test for the component-image-published receiver: updating one
# component must not rewrite any other child image block.
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$root/deploy/helm/envplane/values.yaml" "$tmp/values.before.yaml"
cp "$root/deploy/helm/envplane/values.yaml" "$tmp/values.yaml"
expected_old_reference="$(awk '
  $0 == "envplane-runner:" { in_section=1 }
  in_section && $0 != "envplane-runner:" && $0 ~ /^[^[:space:]]/ { exit }
  in_section && $0 ~ /^    repository:/ { sub(/^    repository:[[:space:]]*/, ""); repository=$0 }
  in_section && $0 ~ /^    tag:/ { sub(/^    tag:[[:space:]]*/, ""); gsub(/"/, ""); tag=$0 }
  END { print repository ":" tag }
' "$tmp/values.before.yaml")"

"$root/scripts/update-runtime-image-values.sh" \
  --component runner \
  --repository ghcr.io/envplane/runner \
  --tag sha-0123456789012345678901234567890123456789 \
  --digest "sha256:$(printf 'a%.0s' {1..64})" \
  --source-revision 0123456789012345678901234567890123456789 \
  --release sha-1123456789012345678901234567890123456789 \
  --values-file "$tmp/values.yaml" \
  --report-file "$tmp/report.json" >/dev/null

for component in control-plane frontend agent; do
  section="envplane-$component"
  awk -v section="$section" '
    $0 == section ":" { in_section=1 }
    in_section && $0 != section ":" && $0 ~ /^[^[:space:]]/ { exit }
    in_section { print }
  ' "$tmp/values.before.yaml" > "$tmp/before-$component"
  awk -v section="$section" '
    $0 == section ":" { in_section=1 }
    in_section && $0 != section ":" && $0 ~ /^[^[:space:]]/ { exit }
    in_section { print }
  ' "$tmp/values.yaml" > "$tmp/after-$component"
  cmp "$tmp/before-$component" "$tmp/after-$component"
done

grep -q 'repository: ghcr.io/envplane/runner' "$tmp/values.yaml"
grep -q 'tag: "sha-0123456789012345678901234567890123456789"' "$tmp/values.yaml"
grep -q 'release: "sha-1123456789012345678901234567890123456789"' "$tmp/values.yaml"
grep -q 'sourceRevision: "0123456789012345678901234567890123456789"' "$tmp/values.yaml"
test "$(jq -r .oldReference "$tmp/report.json")" = "$expected_old_reference"

cp "$tmp/values.yaml" "$tmp/values.before-invalid.yaml"
base_args=(
  --component runner
  --repository ghcr.io/envplane/runner
  --tag sha-0123456789012345678901234567890123456789
  --digest "sha256:$(printf 'b%.0s' {1..64})"
  --source-revision 0123456789012345678901234567890123456789
  --values-file "$tmp/values.yaml"
)
for invalid_release in 'sha-012345678901234567890123456789012345678"' $'sha-0123456789012345678901234567890123456789\ninjected: true'; do
  if "$root/scripts/update-runtime-image-values.sh" "${base_args[@]}" --release "$invalid_release" >/dev/null 2>&1; then
    echo "invalid release was accepted: $invalid_release" >&2
    exit 1
  fi
  cmp "$tmp/values.before-invalid.yaml" "$tmp/values.yaml"
done
echo "component image update isolation test passed"
