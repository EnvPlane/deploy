#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for enabled in false true; do
  options=()
  [[ "$enabled" == false ]] || options+=(--finops-node-inventory)
  bash "$root/scripts/render-remote-cluster-rbac-profile.sh" --cluster-id arbitrary-west \
    --project-id unrelated-project --managed-namespace arbitrary-base "${options[@]}" |
    ENABLED="$enabled" ruby -ryaml -e '
docs = YAML.load_stream(STDIN.read).compact
rules = docs.flat_map { |d| d.fetch("rules", []).map { |r| [d, r] } }
nodes = rules.select { |_, r| r.fetch("resources", []).any? { |name| name.start_with?("nodes") } }
if ENV.fetch("ENABLED") == "false"
  abort "default unexpectedly grants node access" unless nodes.empty?
else
  abort "expected single capability node rule" unless nodes.length == 1
  doc, rule = nodes.first
  abort "node read escaped capability role" unless doc["kind"] == "ClusterRole" && doc.dig("metadata", "name") == "envplane-remote-cluster-arbitrary-west-cluster-capability-reader"
  abort "node inventory is get/list nodes only" unless rule["apiGroups"] == [""] && rule["resources"] == ["nodes"] && rule["verbs"] == ["get", "list"]
  installer = docs.find { |d| d.dig("metadata", "name") == "envplane-remote-cluster-arbitrary-west-installer" }
  abort "installer must retain bounded capability bind" unless installer.fetch("rules").any? { |r| r["verbs"] == ["bind"] && r.fetch("resourceNames", []).include?(doc.dig("metadata", "name")) }
end
'
done
echo 'node inventory profile opt-in contract passed'
