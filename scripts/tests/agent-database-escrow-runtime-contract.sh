#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for enabled in false true; do
  args=(--set "agent.databaseCredentialEscrow.enabled=$enabled")
  if [[ "$enabled" == true ]]; then
    args+=(--set agent.databaseCredentialEscrow.namespace=reviewed-escrow \
      --set agent.databaseCredentialEscrow.keyRef=operator-key-v1 \
      --set agent.databaseCredentialEscrow.keySecret=existing-key \
      --set agent.databaseCredentialEscrow.bindingsSecret=existing-bindings)
  fi
  helm template reviewed "$root/deploy/helm/envplane-agent" "${args[@]}" |
  ruby -ryaml -e '
docs = YAML.load_stream(STDIN.read).compact
pod = docs.find { |d| d["kind"] == "Deployment" }.fetch("spec").fetch("template").fetch("spec")
runtime = pod.fetch("containers").find { |c| c["name"] == "agent" }
env = runtime.fetch("env").to_h { |e| [e["name"], e["value"]] }
abort "missing escrow opt-in env" unless env["ENVPLANE_DB_CREDENTIAL_ESCROW_ENABLED"] == ARGV[0]
mounts = runtime.fetch("volumeMounts", [])
if ARGV[0] == "true"
  abort "missing external namespace" unless env["ENVPLANE_DB_CREDENTIAL_ESCROW_NAMESPACE"] == "reviewed-escrow"
  abort "missing key reference" unless env["ENVPLANE_DB_CREDENTIAL_ESCROW_KEY_REF"] == "operator-key-v1"
  %w[key bindings].each do |part|
    name = "database-escrow-#{part}"
    abort "missing read-only mount" unless mounts.any? { |m| m["name"] == name && m["readOnly"] == true }
    volume = pod.fetch("volumes").find { |v| v["name"] == name }.fetch("secret")
    abort "unexpected Secret permissions" unless volume["defaultMode"] == 288
  end
  abort "key file missing" unless env["ENVPLANE_DB_CREDENTIAL_ESCROW_KEY_FILE"] == "/etc/envplane-db-escrow/key/key"
  abort "binding file missing" unless env["ENVPLANE_DB_CREDENTIAL_ESCROW_BINDINGS_FILE"] == "/etc/envplane-db-escrow/bindings/bindings.json"
else
  abort "disabled escrow mounts key" if mounts.any? { |m| m["name"].start_with?("database-escrow-") }
end
abort "chart must not create escrow/key/bindings Secrets" if docs.any? { |d| d["kind"] == "Secret" && %w[reviewed-escrow existing-key existing-bindings].include?(d.dig("metadata", "name")) }
docs.select { |d| %w[Role ClusterRole].include?(d["kind"]) }.each do |role|
  abort "escrow opt-in must not silently create external RBAC" if role.dig("metadata", "namespace") == "reviewed-escrow"
  role.fetch("rules", []).each do |rule|
    next unless rule.fetch("resources", []).include?("secrets")
    abort "escrow opt-in widened Secret API permissions" if (rule.fetch("verbs", []) & %w[* create update patch delete list watch]).any?
    abort "escrow opt-in grants unrelated key reads" if (rule.fetch("resourceNames", []) & %w[existing-key existing-bindings]).any?
  end
end
puts "Agent database escrow runtime contract passed: #{ARGV[0]}"
' "$enabled"
done
if helm template reviewed "$root/deploy/helm/envplane-agent" --set agent.databaseCredentialEscrow.enabled=true >/dev/null 2>&1; then
  echo "incomplete escrow configuration must fail" >&2
  exit 1
fi
for override in \
  agent.databaseCredentialEscrow.enabled=true \
  agent.databaseCredentialEscrow.unreviewedFlag=true; do
  if helm template reviewed "$root/deploy/helm/envplane-agent" --set-string "$override" >/dev/null 2>&1; then
    echo "escrow schema must reject malformed opt-in: $override" >&2
    exit 1
  fi
done
