#!/usr/bin/env bash
set -euo pipefail

# Fast, cluster-free umbrella contract matrix. It never calls minikube/kind/
# kubectl and validates rendered objects against multiple Kubernetes schemas.
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
KUBECONFORM_CACHE="${KUBECONFORM_CACHE:-$tmp/kubeconform-cache}"
mkdir -p "$KUBECONFORM_CACHE"

profiles=(minimal all-enabled external-databases ingress gateway private-registry existing-secrets)
for profile in "${profiles[@]}"; do
  args=()
  case "$profile" in
    all-enabled) args+=(--set agent.enabled=true --set runner.enabled=true) ;;
    external-databases) args+=(--set 'envpilot-control-plane.postgres.mode=external' --set 'envpilot-control-plane.postgres.external.existingSecret=postgres-connection' --set 'envpilot-control-plane.redis.mode=external' --set 'envpilot-control-plane.redis.external.existingSecret=redis-connection') ;;
    ingress) args+=(--set access.mode=ingress --set access.ingress.host=envpilot.example.test --set access.ingress.className=nginx --set 'platformDependencyReconciler.imagePullSecrets[0].name=registry-credentials') ;;
    gateway) args+=(--set access.mode=gateway --set access.gateway.name=shared-gateway --set 'access.gateway.hostnames[0]=envpilot.example.test') ;;
    private-registry) args+=(--set 'global.envpilot.registry.mode=existing' --set 'global.envpilot.registry.existingSecret=registry-credentials' --set 'envpilot-control-plane.image.repository=registry.example.test/envpilot/api' --set 'envpilot-control-plane.image.tag=0.1.0' --set 'envpilot-frontend.image.repository=registry.example.test/envpilot/frontend' --set 'envpilot-frontend.image.tag=0.1.0') ;;
    existing-secrets) args+=(--set 'envpilot-control-plane.postgres.mode=external' --set 'envpilot-control-plane.postgres.external.existingSecret=postgres-connection' --set 'envpilot-control-plane.redis.mode=external' --set 'envpilot-control-plane.redis.external.existingSecret=redis-connection' --set 'envpilot-agent.controlPlane.existingSecret=agent-credentials' --set 'envpilot-runner.controlPlane.existingSecret=runner-credentials') ;;
  esac
  rendered="$tmp/$profile.yaml"
  helm lint "$CHART_DIR" --namespace envpilot "${args[@]}"
  helm template "envpilot-$profile" "$CHART_DIR" --namespace envpilot "${args[@]}" >"$rendered"
  for version in 1.26.0 1.29.0 1.32.0; do
    kubeconform -strict -ignore-missing-schemas -cache "$KUBECONFORM_CACHE" -kubernetes-version "$version" "$rendered" >/dev/null
  done
  ! rg -q 'envpilot-install|ghcr.io/envpilot/install|kubectl delete namespace|helm (install|upgrade|uninstall)|cluster-admin|resources: \["\*"\]|verbs: \["\*"\]' "$rendered"
  ruby - "$rendered" "$profile" <<'RUBY'
require "yaml"
docs = YAML.load_stream(File.read(ARGV[0])).compact.select { |d| d.is_a?(Hash) }
allowed_namespaces = ["", "envpilot"]
allowed_namespaces << "ingress-nginx" if ARGV[1] == "ingress"
seen = {}
docs.each do |d|
  md = d.fetch("metadata", {})
  key = [d["apiVersion"], d["kind"], md.fetch("namespace", ""), md["name"]]
  abort "duplicate rendered resource: #{key.inspect}" if seen[key]
  seen[key] = true
  ns = md.fetch("namespace", "")
  abort "namespace leakage: #{key.inspect}" unless allowed_namespaces.include?(ns)
end
RUBY
done
