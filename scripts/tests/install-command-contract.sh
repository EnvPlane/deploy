#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readme="$root/README.md"
installation="$root/docs/installation.md"
advanced="$root/docs/installation-advanced.md"
release_index="$root/docs/generated/stable-release-index.json"
renderer="$root/scripts/render-install-docs-from-release-index.sh"
notes="$root/deploy/helm/envplane/templates/NOTES.txt"
preflight="$root/scripts/envplane-install-preflight.sh"

extract_command() {
  awk '
    /<!-- envplane:canonical-install-command:start -->/ { capture=1; next }
    /<!-- envplane:canonical-install-command:end -->/ { exit }
    capture { print }
  ' "$1"
}

install_command="$(jq -er '.install.command' "$release_index")"
version="$(jq -er '.version' "$release_index")"
revision="$(jq -er '.sourceRevision' "$release_index")"
printf -v expected '```bash\n%s\n```' "$install_command"
for document in "$readme" "$installation"; do
  actual="$(extract_command "$document")"
  [[ "$actual" == "$expected" ]] || {
    echo "canonical install command drifted in $document" >&2
    exit 1
  }
done

bash -n "$renderer"
before="$(shasum -a 256 "$readme" "$installation")"
"$renderer" "$release_index" >/dev/null
after="$(shasum -a 256 "$readme" "$installation")"
[[ "$before" == "$after" ]] || { echo "install docs were not rendered from the checked-in release index" >&2; exit 1; }

for document in "$readme" "$installation"; do
  grep -Fq "Stable release: \`$version\`" "$document"
  grep -Fq "blob/$revision/docs/installation.md" "$document"
done

for required in 'Free limits and activation' '## Upgrade' '## Uninstall' '## Troubleshooting'; do
  grep -Fq "$required" "$installation" || { echo "installation guide missing $required" >&2; exit 1; }
done
for required in 'Production hardening' 'Private registry or mirror' 'External PostgreSQL and Redis'; do
  grep -Fq "$required" "$advanced" || { echo "advanced installation guide missing $required" >&2; exit 1; }
done
for warning in 'automatically install an Ingress' 'CSI driver, or cloud integration'; do
  grep -Fq "$warning" "$installation" || { echo "unsupported add-on ownership warning missing: $warning" >&2; exit 1; }
done

bash -n "$preflight"
for forbidden in 'get secret' 'describe secret' '.data' 'kubectl create secret' 'kubectl apply'; do
  if grep -Fq "$forbidden" "$preflight"; then
    echo "preflight must not read, print, or create Secret data: $forbidden" >&2
    exit 1
  fi
done
for required in   'kubectl "${kubectl_args[@]}" auth can-i'   'get storageclass -o jsonpath'   'helm pull "$chart" --version "$version"'   'No resources were created'   'Network check failed'   'Storage check failed'   'RBAC check failed'; do
  grep -Fq "$required" "$preflight" || {
    echo "preflight missing required diagnostic: $required" >&2
    exit 1
  }
done

for required in   'kubectl -n {{ .Release.Namespace }} rollout status deployment/{{ include "envplane-control-plane.fullname" . }} --timeout=10m'   'kubectl -n {{ .Release.Namespace }} port-forward svc/envplane-frontend 3000:3000'   'http://127.0.0.1:3000'; do
  grep -Fq "$required" "$notes" || {
    echo "Helm NOTES missing post-install handoff: $required" >&2
    exit 1
  }
done

echo "canonical install command and post-install handoff contract passed"
