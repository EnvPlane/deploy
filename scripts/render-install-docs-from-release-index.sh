#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
index="${1:-$root/docs/generated/stable-release-index.json}"

[[ -f "$index" ]] || { echo "release index not found: $index" >&2; exit 2; }
for command in jq awk; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 2; }
done

jq -e '
  .schemaVersion == 1 and .channel == "stable" and
  (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.sourceRevision | test("^[0-9a-f]{40}$")) and
  .chart.repository == "oci://ghcr.io/envplane/envplane" and
  (.chart.digest | test("^sha256:[0-9a-f]{64}$")) and
  (.install.command == ("helm upgrade --install envplane " + .chart.repository + " --version " + .version + " --namespace envplane --create-namespace --wait")) and
  ([paths(scalars) as $p | getpath($p) | strings] | join(" ") | test("password|kubeconfig|credential|scm.?token|secret value"; "i") | not)
' "$index" >/dev/null

version="$(jq -er '.version' "$index")"
revision="$(jq -er '.sourceRevision' "$index")"
install_command="$(jq -er '.install.command' "$index")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/command" <<EOF
<!-- envplane:canonical-install-command:start -->
\`\`\`bash
$install_command
\`\`\`
<!-- envplane:canonical-install-command:end -->
EOF

cat > "$tmp/links" <<EOF
<!-- envplane:stable-release-links:start -->
Stable release: \`$version\` · [versioned installation guide](https://github.com/envplane/deploy/blob/$revision/docs/installation.md) · [guided installer](https://envplane-install.alexandr928857.chatgpt.site/install)
<!-- envplane:stable-release-links:end -->
EOF

replace_block() {
  local document="$1" start="$2" end="$3" replacement="$4"
  awk -v start="$start" -v end="$end" -v replacement="$replacement" '
    BEGIN {
      while ((getline line < replacement) > 0) rendered = rendered line "\n"
      close(replacement)
    }
    index($0, start) { printf "%s", rendered; skip=1; next }
    skip && index($0, end) { skip=0; next }
    !skip { print }
  ' "$document" > "$tmp/rendered"
  mv "$tmp/rendered" "$document"
}

for document in "$root/README.md" "$root/docs/installation.md"; do
  replace_block "$document" '<!-- envplane:canonical-install-command:start -->' '<!-- envplane:canonical-install-command:end -->' "$tmp/command"
  replace_block "$document" '<!-- envplane:stable-release-links:start -->' '<!-- envplane:stable-release-links:end -->' "$tmp/links"
done

echo "rendered install docs from stable release index $version"
