#!/usr/bin/env bash
set -euo pipefail

# Contract test for the component-image-published receiver: updating one
# component must not rewrite any other child image block.
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$root/deploy/helm/envpilot/values.yaml" "$tmp/values.before.yaml"
cp "$root/deploy/helm/envpilot/values.yaml" "$tmp/values.yaml"
cp "$root/release/0.3.0.yaml" "$tmp/release.yaml"

"$root/scripts/update-runtime-image-values.sh" \
  --component runner \
  --repository ghcr.io/envpilot/runner \
  --tag sha-0123456789012345678901234567890123456789 \
  --digest "sha256:$(printf 'a%.0s' {1..64})" \
  --source-revision 0123456789012345678901234567890123456789 \
  --values-file "$tmp/values.yaml" \
  --release-file "$tmp/release.yaml" \
  --report-file "$tmp/report.json" >/dev/null

for component in control-plane frontend agent; do
  section="envpilot-$component"
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

grep -q 'repository: ghcr.io/envpilot/runner' "$tmp/values.yaml"
grep -q 'tag: "sha-0123456789012345678901234567890123456789"' "$tmp/release.yaml"
grep -q 'sourceRevision: "0123456789012345678901234567890123456789"' "$tmp/release.yaml"
test "$(jq -r .oldReference "$tmp/report.json")" = "ghcr.io/envpilot/runner:0.1.4"
echo "component image update isolation test passed"
