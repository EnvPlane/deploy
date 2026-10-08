#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
renderer="$root/scripts/render-remote-cluster-rbac-profile.sh"
rendered="$(mktemp "${TMPDIR:-/tmp}/envplane-remote-rbac.XXXXXX")"
trap 'rm -f "$rendered"' EXIT

bash "$renderer" --cluster-id customer-west --runtime-namespace envplane-system --managed-namespace base-api --managed-namespace base-api >"$rendered"

RENDERED="$rendered" ruby -ryaml -e '
docs = YAML.load_stream(File.read(ENV.fetch("RENDERED"))).compact
identities = docs.map do |doc|
  next unless doc.is_a?(Hash) && doc["kind"] && doc.dig("metadata", "name")
  [doc["apiVersion"], doc["kind"], doc.dig("metadata", "namespace").to_s, doc.dig("metadata", "name")]
end.compact
duplicates = identities.group_by(&:itself).select { |_identity, entries| entries.length > 1 }.keys
abort "renderer emitted duplicate Kubernetes identities: #{duplicates.inspect}" unless duplicates.empty?
puts "renderer Kubernetes identities are unique"
metrics = docs.select { |d| d.is_a?(Hash) && d.fetch("rules", []).any? { |r| r["apiGroups"] == ["metrics.k8s.io"] } }
expected = ["envplane-remote-cluster-customer-west-discovery-parent", "envplane-remote-cluster-customer-west-discovery-reader"]
abort "unexpected metrics roles" unless metrics.map { |d| d.dig("metadata", "name") }.sort == expected.sort
metrics.each do |doc|
  doc["rules"].select { |r| r["apiGroups"] == ["metrics.k8s.io"] }.each do |rule|
    abort "metrics must be get/list pods only" unless rule["resources"] == ["pods"] && rule["verbs"] == ["get", "list"]
  end
end
parent = expected.first
bindings = docs.select { |d| d.is_a?(Hash) && d.dig("roleRef", "name") == parent }
abort "metrics parent must not grant cluster-wide access" if bindings.any? { |d| d["kind"] != "RoleBinding" }
abort "metrics parent binding namespace escaped allowlist" unless bindings.all? { |d| ["base-api", "envplane-system"].include?(d.dig("metadata", "namespace")) }
'

grep -Fq 'name: envplane-remote-cluster-customer-west-cluster-capability-reader' "$rendered"
grep -A8 -F 'kind: Namespace' "$rendered" | grep -Fq 'pod-security.kubernetes.io/enforce: restricted'
grep -A12 -F 'kind: ServiceAccount' "$rendered" | grep -Fq 'automountServiceAccountToken: false'
grep -A12 -F 'kind: ServiceAccount' "$rendered" | grep -Fq 'envplane.io/owner: local-platform'
grep -Fq 'name: envplane-remote-cluster-customer-west-namespace-inventory-reader' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-namespace-metadata-reader' "$rendered"
grep -A5 -F 'name: envplane-remote-cluster-customer-west-namespace-metadata-reader' "$rendered" | grep -Fq 'resourceNames:'
grep -A12 -F 'name: envplane-remote-cluster-customer-west-namespace-metadata-reader' "$rendered" | grep -Fq '      - base-api'
grep -A8 -F '      - envplane-remote-cluster-customer-west-namespace-metadata-reader' "$rendered" | grep -Fq 'verbs: ["get", "update", "patch"]'
grep -Fq 'name: envplane-remote-cluster-customer-west-feature-env-writer-parent' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-runtime-manager' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-discovery-reader' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-discovery-parent' "$rendered"
grep -Fq 'namespace: base-api' "$rendered"
discovery="$(awk '/name: envplane-remote-cluster-customer-west-discovery-reader$/{capture=1} capture{print} /^---$/{if (capture) exit}' "$rendered")"
if grep -Eq 'secrets|create|update|patch|delete' <<<"$discovery"; then
  echo 'discovery-only Role must not grant Secret access or write verbs' >&2
  exit 1
fi
if grep -Fq 'name: envplane-remote-cluster-customer-west-flux-reader' "$rendered"; then
  echo 'Flux scope must remain opt-in' >&2
  exit 1
fi
flux_rendered="$(bash "$renderer" --cluster-id customer-west --managed-namespace base-api --flux-namespace base-api)"
grep -Fq 'name: envplane-remote-cluster-customer-west-flux-reader' <<<"$flux_rendered"
grep -Fq 'namespace: base-api' "$rendered"
grep -Fq 'kind: ValidatingAdmissionPolicy' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-installer-clusterrole-scope' "$rendered"
grep -Fq 'name: envplane-remote-cluster-customer-west-installer-clusterrolebinding-scope' "$rendered"
grep -Fq 'oldObject.roleRef.name' "$rendered"
grep -Fq "oldObject.metadata.name.matches('^ep-agent-" "$rendered"
grep -Fq 'oldObject.roleRef.name == oldObject.metadata.name' "$rendered"
grep -Fq 'subject.namespace == "envplane-system"' "$rendered"
grep -Fq "oldObject.metadata.labels['app.kubernetes.io/managed-by'] == \"Helm\"" "$rendered"
grep -Fq "object.metadata.labels['app.kubernetes.io/component'] == \"cluster-agent\"" "$rendered"
grep -Fq 'remote installer may manage only bounded Helm-owned Runner namespace-reader ClusterRoles' "$rendered"
grep -Fq 'remote installer may bind only fixed capability roles or bounded Helm-owned Runner namespace readers' "$rendered"
policy="$(awk '/kind: ValidatingAdmissionPolicy$/{capture=1} capture{print} /^---$/{if (capture) exit}' "$rendered")"
if grep -Fq 'feature-env-writer-parent' <<<"$policy"; then
  echo 'remote installer admission policy must not allow feature-env-writer-parent ClusterRoleBindings' >&2
  exit 1
fi
if grep -Eq 'resources: \["\*"\]|verbs: \["\*"\]' "$rendered"; then
  echo 'remote cluster profile must not grant wildcard permissions' >&2
  exit 1
fi
if ! grep -Fq "object.metadata.name.matches('^ep-runner-" "$rendered"; then
  echo 'remote cluster profile must limit dynamic Runner ClusterRoles by canonical release name' >&2
  exit 1
fi
if ! grep -Fq 'object.rules[0].resources == ["namespaces"]' "$rendered" || ! grep -Fq 'object.rules[0].resourceNames.size() >= 1' "$rendered"; then
  echo 'remote cluster profile must require concrete namespace-only Runner rules' >&2
  exit 1
fi
if ! grep -Fq 'object.metadata.name == "envplane-remote-cluster-customer-west-namespace-metadata-reader"' "$rendered"; then
  echo 'remote cluster profile must retain bounded updates to the fixed namespace metadata reader' >&2
  exit 1
fi
if ! grep -A6 -F 'resources: ["clusterroles"]' "$rendered" | grep -Fq 'verbs: ["bind"]'; then
  echo 'remote cluster profile must allow the bounded Runner ClusterRole to be bound' >&2
  exit 1
fi
if ! grep -Fq 'object.subjects.size() == 1' "$rendered" || ! grep -Fq 'object.roleRef.name == object.metadata.name' "$rendered"; then
  echo 'remote cluster profile must constrain dynamic Runner ClusterRoleBindings' >&2
  exit 1
fi
if bash "$renderer" --cluster-id 'BAD_Name' >/dev/null 2>&1; then
  echo 'renderer accepted an invalid cluster ID' >&2
  exit 1
fi
if bash "$renderer" --cluster-id customer-west --service-account custom-agent >/dev/null 2>&1; then
  echo 'renderer accepted an unsupported custom ServiceAccount identity' >&2
  exit 1
fi
for option in --cluster-id --runtime-namespace --managed-namespace --flux-namespace --flux-status-reader-namespace --project-id --deployment-backend --flux-control-namespace; do
  if bash "$renderer" "$option" >/dev/null 2>&1; then
    echo "renderer accepted missing value for $option" >&2
    exit 1
  fi
done

if grep -Fq 'dynamic-flux-status-get-v1' "$rendered"; then
  echo 'dynamic Flux parent must remain opt-in' >&2; exit 1
fi
status_profile="$(bash "$renderer" --cluster-id customer-west --runtime-namespace runtime --project-id arbitrary-orders --flux-status-reader-namespace team-flux --flux-status-reader-namespace team-flux)"
PROFILE="$status_profile" ruby -ryaml -e '
docs=YAML.load_stream(ENV.fetch("PROFILE")).compact
name="envplane-remote-cluster-customer-west-flux-status-parent"
roles=docs.select { |d| d["kind"] == "Role" && d.dig("metadata", "name") == name }
abort "duplicate or missing Flux parent" unless roles.size == 1
role=roles.first
abort "wrong namespace" unless role.dig("metadata", "namespace") == "team-flux"
expected=[{"apiGroups"=>["kustomize.toolkit.fluxcd.io"], "resources"=>["kustomizations"], "verbs"=>["get"]}]
abort "Flux parent grants additional privileges" unless role["rules"] == expected
binding=docs.find { |d| d["kind"] == "RoleBinding" && d.dig("metadata", "name") == name }
abort "wrong installer identity" unless binding["subjects"] == [{"kind"=>"ServiceAccount", "name"=>"envplane-remote-cluster-customer-west", "namespace"=>"runtime"}]
abort "wrong role reference" unless binding["roleRef"] == {"apiGroup"=>"rbac.authorization.k8s.io", "kind"=>"Role", "name"=>name}
'
if bash "$renderer" --cluster-id customer-west --flux-status-reader-namespace '../foreign' >/dev/null 2>&1; then
  echo 'renderer accepted invalid Flux status namespace' >&2; exit 1
fi

reviewed="$(bash "$renderer" --cluster-id bethunder-local --project-id app --project-id arbitrary-orders --project-id app --runtime-namespace runtime)"
PROFILE="$reviewed" ruby -ryaml -e '
docs=YAML.load_stream(ENV.fetch("PROFILE")).compact
role=docs.find { |d| d["kind"] == "ClusterRole" && d.dig("metadata", "name") == "envplane-remote-cluster-bethunder-local-installer" }
abort "wrong profile version" unless role.dig("metadata", "annotations", "envplane.io/access-profile") == "dynamic-project-bindings-v1"
names=role.dig("metadata", "annotations", "envplane.io/reviewed-project-bindings").split(",")
abort "project bindings missing or duplicated" unless names.size == 6 && names.uniq.size == 6
rule=role.fetch("rules").find { |r| r["resources"] == ["clusterrolebindings"] }
abort "future project names incorrectly restricted" if rule.key?("resourceNames")
abort "missing lifecycle verbs" unless (["get", "create", "update", "patch", "delete"] - rule.fetch("verbs")).empty?
'
for project_id in app arbitrary-orders; do
  names="$(bash "$root/scripts/render-remote-project-binding-access.sh" --cluster-id bethunder-local --project-id "$project_id" --runtime-namespace runtime | awk '/^      - / {print $2}')"
  while IFS= read -r name; do grep -Fq "$name" <<<"$reviewed"; done <<<"$names"
done
if bash "$renderer" --cluster-id customer-west --project-id '../foreign' >/dev/null 2>&1; then
  echo 'renderer accepted invalid project ID' >&2; exit 1
fi

chart="$root/deploy/helm/envplane-agent"
agent_rendered="$(mktemp "${TMPDIR:-/tmp}/envplane-remote-agent-rbac.XXXXXX")"
trap 'rm -f "$rendered" "$agent_rendered"' EXIT
helm template remote-agent "$chart" --namespace envplane-system \
  --set rbac.discovery.scope=namespace \
  --set rbac.discovery.clusterCapabilityRead=true \
  --set 'rbac.discovery.existingClusterRoles[0]=envplane-remote-cluster-customer-west-cluster-capability-reader' \
  --set 'rbac.discovery.existingClusterRoles[1]=envplane-remote-cluster-customer-west-namespace-inventory-reader' \
  --set 'rbac.discovery.existingClusterRoles[2]=envplane-remote-cluster-customer-west-namespace-metadata-reader' \
  --set 'rbac.discovery.namespaces[0]=base-api' \
  --set managedRemote.enabled=true \
  --set managedRemote.remoteClusterId=customer-west \
  --set managedRemote.projectId=platform \
  --set managedRemote.authRevision=generation-1 \
  --set managedRemote.compatibilityPin=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  --set managedRemote.generation=1 \
  --set 'managedRemote.targetNamespaces[0]=base-api' \
  --set controlPlane.endpointMode=remote \
  --set controlPlane.url=https://control.example.test \
  --set controlPlane.existingSecret=agent-bootstrap >"$agent_rendered"
if grep -A3 -F 'kind: ClusterRole' "$agent_rendered" | grep -Fq 'remote-agent-envplane-agent-cluster-capability-reader'; then
  echo 'managed remote Agent must bind the fixed capability role instead of rendering a release-named ClusterRole' >&2
  exit 1
fi
grep -Fq 'name: envplane-remote-cluster-customer-west-cluster-capability-reader' "$agent_rendered"

echo 'remote cluster RBAC profile contract is valid'
