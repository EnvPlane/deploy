#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output="$(bash "$root/scripts/render-remote-project-binding-access.sh" --cluster-id bethunder-local --project-id app)"
grep -Fq 'ep-agent-c05a23617cac-envplane-agent-capability-637e570683' <<<"$output"
if grep -Eq 'verbs:.*(create|bind|escalate|\*)' <<<"$output"; then echo "unexpected privilege" >&2; exit 1; fi
printf '%s' "$output" | ruby -ryaml -e 'docs=YAML.load_stream(STDIN.read); rules=docs[0].fetch("rules"); abort unless rules.size==1 && rules[0].fetch("resourceNames").size==3 && docs[1].fetch("subjects").size==1'
other="$(bash "$root/scripts/render-remote-project-binding-access.sh" --cluster-id customer-west --project-id arbitrary-orders --runtime-namespace runtime)"
if grep -Fq 'ep-agent-c05a23617cac' <<<"$other"; then exit 1; fi
if bash "$root/scripts/render-remote-project-binding-access.sh" --cluster-id west --project-id '../foreign' >/dev/null 2>&1; then exit 1; fi

# Compare identities with the real chart, including a non-default namespace
# and arbitrary project ID. This catches release/hash or chart-name drift.
for project_id in app arbitrary-orders; do
  project_hash="$(printf '%s' "$project_id:agent" | shasum -a 256 | cut -c1-12)"
  chart_output="$(helm template "ep-agent-$project_hash" "$root/deploy/helm/envplane-agent" \
    --namespace runtime --show-only templates/rbac.yaml \
    --set rbac.discovery.scope=namespace --set rbac.discovery.clusterCapabilityRead=true \
    --set 'rbac.discovery.existingClusterRoles[0]=envplane-remote-cluster-customer-west-cluster-capability-reader' \
    --set 'rbac.discovery.existingClusterRoles[1]=envplane-remote-cluster-customer-west-namespace-metadata-reader' \
    --set 'rbac.discovery.existingClusterRoles[2]=envplane-remote-cluster-customer-west-namespace-inventory-reader')"
  expected="$(bash "$root/scripts/render-remote-project-binding-access.sh" --cluster-id customer-west --project-id "$project_id" --runtime-namespace runtime | awk '/^      - / {print $2}')"
  CHART="$chart_output" EXPECTED="$expected" ruby -ryaml -e '
    names=YAML.load_stream(ENV.fetch("CHART")).compact.select { |d| d["kind"] == "ClusterRoleBinding" }.map { |d| d.dig("metadata", "name") }.sort
    abort "project binding names diverge from chart" unless names == ENV.fetch("EXPECTED").split.sort
  '
done
echo "remote project exact binding access contract passed"
