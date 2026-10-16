#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helm_bin="${HELM_BIN:-helm}"
fixture="$chart_dir/tests/fixtures/platform-dependencies/traefik-managed.yaml"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

"$helm_bin" template test "$chart_dir" --namespace envplane -f "$fixture" > "$rendered"
ruby - "$rendered" <<'RUBY'
require "yaml"
docs = YAML.load_stream(File.read(ARGV.fetch(0))).compact
job = docs.find { |d| d["kind"] == "Job" && d.dig("metadata", "name") == "test-platform-reconciler" }
abort "missing regular reconciler Job" unless job
env = job.dig("spec", "template", "spec", "containers", 0, "env")
skip = env.find { |e| e["name"] == "ENVPLANE_RECONCILE_SKIP_MANAGED_INGRESS" }
abort "managed Traefik was silently skipped" unless skip && skip["value"] == "false"
abort "nginx installer leaked into Traefik profile" if docs.any? { |d| d.dig("metadata", "name") == "test-platform-ingress-installer" }
RUBY

"$helm_bin" template test "$chart_dir" --namespace envplane \
  --set access.mode=ingress --set access.ingress.host=envplane.example.test \
  --set access.ingress.className=nginx --set access.ingress.tls.enabled=true \
  --set access.ingress.tls.secretName=test-tls > "$rendered"
ruby - "$rendered" <<'RUBY'
require "yaml"
docs = YAML.load_stream(File.read(ARGV.fetch(0))).compact
job = docs.find { |d| d["kind"] == "Job" && d.dig("metadata", "name") == "test-platform-reconciler" }
env = job.dig("spec", "template", "spec", "containers", 0, "env")
skip = env.find { |e| e["name"] == "ENVPLANE_RECONCILE_SKIP_MANAGED_INGRESS" }
abort "legacy nginx installer path changed" unless skip && skip["value"] == "true"
abort "legacy nginx installer missing" unless docs.any? { |d| d.dig("metadata", "name") == "test-platform-ingress-installer" }
RUBY

if "$helm_bin" template test "$chart_dir" --namespace envplane -f "$fixture" \
  --set-string platformDependencies.ingress.managed.chartSha256=bad > /dev/null 2>&1; then
  echo "invalid managed chart checksum passed schema validation" >&2
  exit 1
fi
if "$helm_bin" template test "$chart_dir" --namespace envplane -f "$fixture" \
  --set-string platformDependencies.ingress.namespace= > /dev/null 2>&1; then
  echo "Traefik without a namespace passed schema validation" >&2
  exit 1
fi

echo "Traefik provider chart contract passed"
