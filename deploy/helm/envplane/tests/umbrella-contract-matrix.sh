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
  # This matrix is a cluster-free render test and has no PostgreSQL CA Secret
  # fixture. Keep the production TLS default intact, but make the test input
  # explicit so rendering does not depend on a cluster-provided Secret.
  args+=(--set 'envplane-control-plane.postgres.tls.enabled=false')
  case "$profile" in
    all-enabled) args+=(--set agent.enabled=true --set runner.enabled=true) ;;
    external-databases) args+=(--set 'envplane-control-plane.postgres.mode=external' --set 'envplane-control-plane.postgres.external.existingSecret=postgres-connection' --set 'envplane-control-plane.redis.mode=external' --set 'envplane-control-plane.redis.external.existingSecret=redis-connection') ;;
    ingress) args+=(--set access.mode=ingress --set access.ingress.host=envplane.example.test --set access.ingress.className=nginx --set access.ingress.tls.enabled=true --set access.ingress.tls.secretName=envplane-test-tls --set 'platformDependencyReconciler.imagePullSecrets[0].name=registry-credentials') ;;
    gateway) args+=(--set access.mode=gateway --set access.gateway.name=shared-gateway --set 'access.gateway.hostnames[0]=envplane.example.test') ;;
    private-registry) args+=(--set 'global.envplane.registry.mode=existing' --set 'global.envplane.registry.existingSecret=registry-credentials' --set 'envplane-control-plane.image.repository=registry.example.test/envplane/api' --set 'envplane-control-plane.image.tag=0.1.0' --set 'envplane-frontend.image.repository=registry.example.test/envplane/frontend' --set 'envplane-frontend.image.tag=0.1.0') ;;
    existing-secrets) args+=(--set 'envplane-control-plane.postgres.mode=external' --set 'envplane-control-plane.postgres.external.existingSecret=postgres-connection' --set 'envplane-control-plane.redis.mode=external' --set 'envplane-control-plane.redis.external.existingSecret=redis-connection' --set 'envplane-agent.controlPlane.existingSecret=agent-credentials' --set 'envplane-runner.controlPlane.existingSecret=runner-credentials') ;;
  esac
  rendered="$tmp/$profile.yaml"
  helm lint "$CHART_DIR" --namespace envplane "${args[@]}"
  helm template "envplane-$profile" "$CHART_DIR" --namespace envplane "${args[@]}" >"$rendered"
  for version in 1.26.0 1.29.0 1.32.0; do
    kubeconform -strict -ignore-missing-schemas -cache "$KUBECONFORM_CACHE" -kubernetes-version "$version" "$rendered" >/dev/null
  done
  ! rg -q 'envplane-install|ghcr.io/envplane/install|kubectl delete namespace|helm (install|upgrade|uninstall)|cluster-admin|resources: \["\*"\]|verbs: \["\*"\]' "$rendered"
  ruby - "$rendered" "$profile" <<'RUBY'
require "yaml"
docs = YAML.load_stream(File.read(ARGV[0])).compact.select { |d| d.is_a?(Hash) }
allowed_namespaces = ["", "envplane"]
allowed_namespaces << "ingress-nginx" if ARGV[1] == "ingress"
# The all-enabled profile intentionally exercises the Agent's default
# namespaced discovery target. Its Role and RoleBinding belong in `default`;
# this is an explicit workload scope, not an accidental namespace leak.
allowed_namespaces << "default" if ARGV[1] == "all-enabled"
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
