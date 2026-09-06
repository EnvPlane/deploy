#!/usr/bin/env bash
# Render the Runner writer contract and verify that the control-plane release
# manager still holds every permission it must delegate to a Runner.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
runner_render="$(mktemp "${TMPDIR:-/tmp}/envplane-runner-rbac.XXXXXX")"
control_render="$(mktemp "${TMPDIR:-/tmp}/envplane-control-plane-rbac.XXXXXX")"
trap 'rm -f "$runner_render" "$control_render"' EXIT

helm template envplane-runner "$root/deploy/helm/envplane-runner" \
  --namespace envplane >"$runner_render"
helm template envplane-control-plane "$root/deploy/helm/envplane-control-plane" \
  --namespace envplane \
  --set postgres.tls.enabled=false \
  --set global.envplane.firstStartRegistration.mode=managed \
  --set global.envplane.firstStartRegistration.project.id=envplane \
  --set global.envplane.firstStartRegistration.project.productId=generic \
  --set global.envplane.firstStartRegistration.agent.id=envplane-agent \
  --set global.envplane.firstStartRegistration.runner.id=envplane-runner \
  --set global.envplane.firstStartRegistration.runner.deploymentMode=helm \
  --set global.envplane.firstStartRegistration.cluster.id=contract-test \
  --set global.envplane.sameClusterProjectExecutors.enabled=true \
  --set global.envplane.sameClusterProjectExecutors.namespace=envplane-executors \
  --set rbac.sameClusterProjectExecutors.enabled=true \
  --set rbac.sameClusterProjectExecutors.namespace=envplane-executors \
  >"$control_render"

RUNNER_RENDER="$runner_render" CONTROL_RENDER="$control_render" ruby -ryaml -e '
def expanded_rules(path, kind, name)
  docs = YAML.load_stream(File.read(path))
  rules = docs.each_with_object([]) do |doc, selected|
    next unless doc.is_a?(Hash) && doc["kind"] == kind && doc.dig("metadata", "name") == name
    selected.concat(doc.fetch("rules"))
  end
  rules.each_with_object({}) do |rule, expanded|
    Array(rule["apiGroups"]).each do |group|
      Array(rule["resources"]).each do |resource|
        Array(rule["verbs"]).each do |verb|
          expanded[[group, resource, verb]] = true
        end
      end
    end
  end.keys
end

runner = expanded_rules(ENV.fetch("RUNNER_RENDER"), "Role", "envplane-runner-feature-env-writer")
control = expanded_rules(ENV.fetch("CONTROL_RENDER"), "ClusterRole", "envplane-control-plane-same-cluster-project-executor-release-manager")
runner_set = runner.each_with_object({}) { |entry, set| set[entry] = true }
control_set = control.each_with_object({}) { |entry, set| set[entry] = true }
missing = runner_set.keys.reject { |entry| control_set[entry] }
if missing.any?
  abort "control-plane release manager is missing Runner feature-env-writer permissions: #{missing.inspect}"
end

# Only compare the resources owned by the Runner writer. The release manager
# intentionally has additional read-only permissions for Agent and Flux.
runner_resources = runner_set.keys.map { |group, resource, _verb| [group, resource] }.uniq
control_writer = control_set.keys.select { |group, resource, _verb| runner_resources.include?([group, resource]) }
unless control_writer.sort == runner_set.keys.sort
  abort "control-plane feature-env-writer permissions diverged from the Runner contract"
end
puts "feature-env-writer RBAC contract is valid"
'
