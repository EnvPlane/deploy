#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readme="$root/README.md"
installation="$root/docs/installation.md"
notes="$root/deploy/helm/envplane/templates/NOTES.txt"
preflight="$root/scripts/envplane-install-preflight.sh"

extract_command() {
  awk '
    /<!-- envplane:canonical-install-command:start -->/ { capture=1; next }
    /<!-- envplane:canonical-install-command:end -->/ { exit }
    capture { print }
  ' "$1"
}

expected="$(cat <<'EOF'
```bash
helm upgrade --install envplane oci://ghcr.io/envplane/envplane \
  --version <published-umbrella-version> \
  --namespace envplane \
  --create-namespace \
  --wait
```
EOF
)"
for document in "$readme" "$installation"; do
  actual="$(extract_command "$document")"
  [[ "$actual" == "$expected" ]] || {
    echo "canonical install command drifted in $document" >&2
    exit 1
  }
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
