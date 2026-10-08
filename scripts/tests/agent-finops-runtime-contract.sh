#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helm template reviewed "$root/deploy/helm/envplane-agent" \
  --set agent.finops.prometheusEndpoint=https://metrics.private:9090 \
  --set agent.finops.allowedOrigins[0]=https://metrics.private:9090 \
  --set agent.finops.cadvisorContainerdUIDEnabled=true \
  --set agent.finops.caSecret=reviewed-public-ca \
  --set agent.finops.caKey=ca.crt \
  --set agent.finops.tlsServerName=metrics.private \
  --set agent.finops.storageUsedMetric=envplane_pvc_directory_allocated_bytes |
ruby -ryaml -e '
deployment = YAML.load_stream(STDIN.read).compact.find { |d| d["kind"] == "Deployment" }
spec = deployment.fetch("spec").fetch("template").fetch("spec")
runtime = spec.fetch("containers").find { |c| c["name"] == "agent" }
env = runtime.fetch("env").to_h { |e| [e["name"], e["value"]] }
expected = {
  "ENVPLANE_FINOPS_PROMETHEUS_ENDPOINT" => "https://metrics.private:9090",
  "ENVPLANE_FINOPS_PROMETHEUS_ALLOWED_ORIGINS" => "https://metrics.private:9090",
  "ENVPLANE_FINOPS_CADVISOR_CONTAINERD_UID_ENABLED" => "true",
  "ENVPLANE_FINOPS_PROMETHEUS_CA_FILE" => "/etc/envplane-finops-ca/ca.crt",
  "ENVPLANE_FINOPS_PROMETHEUS_TLS_SERVER_NAME" => "metrics.private",
  "ENVPLANE_FINOPS_STORAGE_USED_METRIC" => "envplane_pvc_directory_allocated_bytes"
}
abort "FinOps profile missing from actual Agent runtime container" unless expected.all? { |k, v| env[k] == v }
abort "public CA mount missing on runtime" unless runtime.fetch("volumeMounts").any? { |m| m["name"] == "finops-ca" && m["readOnly"] == true }
puts "Agent runtime FinOps contract passed"
'
