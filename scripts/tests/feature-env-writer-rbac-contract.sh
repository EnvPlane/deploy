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
  --kube-version 1.30.0 \
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
if unverified_render="$(helm template envplane-control-plane "$root/deploy/helm/envplane-control-plane" \
    --kube-version 1.30.0 --namespace envplane --set postgres.tls.enabled=false \
    --set rbac.sameClusterProjectExecutors.enabled=true \
    --set rbac.sameClusterProjectExecutors.namespace=envplane-executors \
    --set-string rbac.sameClusterProjectExecutors.networkPolicyAdmissionUID=unverified \
    2>&1)" || ! grep -q "verify the exact preview admission binding" <<<"$unverified_render"; then
  echo "control-plane chart accepted an unverified binding UID" >&2
  exit 1
fi

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

policy_render="$(mktemp "${TMPDIR:-/tmp}/envplane-policy-rbac.XXXXXX")"
legacy_render="$(mktemp "${TMPDIR:-/tmp}/envplane-legacy-rbac.XXXXXX")"
trap 'rm -f "$runner_render" "$control_render" "$policy_render" "$legacy_render"' EXIT
runner_args=(
  --namespace envplane-executors
  --set rbac.featureEnvWriter.mode=preconfiguredNamespaces
  --set 'rbac.featureEnvWriter.namespaces[0]=envplane-pr-policy-contract'
  --set 'rbac.featureEnvWriter.namespaces[1]=envplane-pr-no-policy'
  --set 'rbac.featureEnvWriter.namespaceCapabilities[0].namespace=envplane-pr-policy-contract'
  --set 'rbac.featureEnvWriter.namespaceCapabilities[0].allowNetworkPolicies=true'
)
managed_args=(
  --set managedSameCluster.enabled=true
  --set envplaneOwnership=same-cluster-project-reconciler
  --set controlPlane.endpointMode=sameCluster
  --set controlPlane.serviceName=envplane-control-plane
)
helm template ep-runner-contract "$root/deploy/helm/envplane-runner" \
  --kube-version 1.30.0 "${runner_args[@]}" "${managed_args[@]}" >"$policy_render"
helm template ep-runner-contract "$root/deploy/helm/envplane-runner" \
  --kube-version 1.29.0 "${runner_args[@]}" >"$legacy_render"
if helm template ep-runner-contract "$root/deploy/helm/envplane-runner" \
    --kube-version 1.29.0 "${runner_args[@]}" "${managed_args[@]}" >"$runner_render" 2>&1 ||
    ! grep -q 'managed NetworkPolicy delegation requires Kubernetes 1.30 or later' "$runner_render"; then
  abort_message="managed NetworkPolicy delegation did not fail closed on Kubernetes 1.29"
  echo "$abort_message" >&2
  exit 1
fi
if helm template ep-runner-contract "$root/deploy/helm/envplane-runner" \
    --kube-version 1.30.0 "${runner_args[@]}" "${managed_args[@]}" \
    --set 'rbac.featureEnvWriter.namespaces[0]=default' \
    --set 'rbac.featureEnvWriter.namespaceCapabilities[0].namespace=default' >"$runner_render" 2>&1 ||
    ! grep -q 'requires a dedicated preview namespace' "$runner_render"; then
  echo "managed NetworkPolicy delegation accepted a non-preview namespace" >&2
  exit 1
fi

CONTROL_RENDER="$control_render" POLICY_RENDER="$policy_render" LEGACY_RENDER="$legacy_render" ruby -ryaml -e '
def docs(key)
  YAML.load_stream(File.read(ENV.fetch(key))).select { |doc| doc.is_a?(Hash) }
end
def named(docs, kind, name)
  docs.find { |doc| doc["kind"] == kind && doc.dig("metadata", "name") == name } ||
    abort("missing #{kind}/#{name}")
end
def network_policy_rules(resource)
  resource.fetch("rules").select do |rule|
    rule.fetch("apiGroups").include?("networking.k8s.io") &&
      rule.fetch("resources").include?("networkpolicies")
  end
end
role_name = "envplane-control-plane-preview-networkpolicy-writer"
control = docs("CONTROL_RENDER")
manager = named(control, "ClusterRole", "envplane-control-plane-same-cluster-project-executor-release-manager")
abort "manager has direct NetworkPolicy writes" if network_policy_rules(manager).any? do |rule|
  (rule.fetch("verbs") - %w[get list watch]).any?
end
bind = manager.fetch("rules").select { |rule| rule.fetch("verbs").include?("bind") }
abort "unverified install must not render the bind grant" unless bind.empty?
writer = named(control, "ClusterRole", role_name)
abort "delegated role is broader than NetworkPolicy" unless writer.fetch("rules") == [{
  "apiGroups" => ["networking.k8s.io"], "resources" => ["networkpolicies"],
  "verbs" => %w[get list watch create update patch delete]
}]
policy = named(control, "ValidatingAdmissionPolicy", role_name)
binding = named(control, "ValidatingAdmissionPolicyBinding", role_name)
abort "binding must enforce the exact admission policy" unless binding.fetch("spec") == {
  "policyName" => role_name, "validationActions" => ["Deny"]
}
abort "policy must fail closed" unless policy.dig("spec", "failurePolicy") == "Fail"
rule = policy.dig("spec", "matchConstraints", "resourceRules").first
abort "policy must guard both binding kinds" unless rule.fetch("resources").sort == %w[clusterrolebindings rolebindings]

managed = docs("POLICY_RENDER")
bindings = managed.select { |doc| doc.dig("roleRef", "name") == role_name }
abort "expected one binding and only in the opted-in namespace" unless bindings.size == 1 &&
  bindings.first["kind"] == "RoleBinding" &&
  bindings.first.dig("metadata", "namespace") == "envplane-pr-policy-contract" &&
  bindings.first["subjects"] == [{
    "kind" => "ServiceAccount", "name" => "ep-runner-contract-envplane-runner",
    "namespace" => "envplane-executors"
  }]
abort "managed roles must not duplicate the delegation" if managed.any? do |doc|
  doc["kind"] == "Role" && network_policy_rules(doc).any?
end
legacy = docs("LEGACY_RENDER")
legacy_writer = legacy.find do |doc|
  doc["kind"] == "Role" && doc.dig("metadata", "namespace") == "envplane-pr-policy-contract" &&
    doc.dig("metadata", "name").end_with?("-feature-env-writer")
end
abort "remote Runner lost namespace-local policy writes" unless legacy_writer &&
  network_policy_rules(legacy_writer).any? { |rule| rule.fetch("verbs").include?("create") } &&
  legacy.none? { |doc| doc.dig("roleRef", "name") == role_name }
puts "managed NetworkPolicy delegation contract is valid"
'
