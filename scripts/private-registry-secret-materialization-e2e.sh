#!/usr/bin/env bash
# Disposable SM-09 release gate. It intentionally creates every Kubernetes and
# registry resource it needs, never prints registry credentials, and runs
# before the umbrella OCI artifact is published.
set -euo pipefail

: "${ENVPLANE_SM09_CHART:?set the packaged umbrella chart path}"

cluster="${ENVPLANE_SM09_CLUSTER:-envplane-sm09}"
registry="${ENVPLANE_SM09_REGISTRY:-localhost:5001}"
registry_name="${ENVPLANE_SM09_REGISTRY_CONTAINER:-envplane-sm09-registry}"
namespace="${ENVPLANE_SM09_NAMESPACE:-envplane-sm09}"
base_namespace="${ENVPLANE_SM09_BASE_NAMESPACE:-envplane-sm09-base}"
target_namespace="${ENVPLANE_SM09_TARGET_NAMESPACE:-envplane-sm09-target}"
project="${ENVPLANE_SM09_PROJECT:-envplane-e2e-fixture}"
environment="${ENVPLANE_SM09_ENVIRONMENT:-sm09-private-registry}"
release="${ENVPLANE_SM09_RELEASE:-envplane-sm09}"
tmp="$(mktemp -d)"
pids=()

cleanup() {
  for pid in "${pids[@]:-}"; do kill "$pid" >/dev/null 2>&1 || true; done
  kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
  docker rm -f "$registry_name" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

for bin in docker kind kubectl helm curl jq; do command -v "$bin" >/dev/null || { echo "missing $bin" >&2; exit 2; }; done
[[ -f "$ENVPLANE_SM09_CHART" ]] || { echo "packaged umbrella chart is missing" >&2; exit 2; }

# Credentials are generated only in memory/files with restrictive permissions.
# Neither `set -x` nor an echo of these values is permitted in this harness.
registry_user="envplane"
registry_password="$(openssl rand -hex 24)"
application_secret="$(openssl rand -hex 24)"
umask 077
mkdir -p "$tmp/auth"
docker run --rm --entrypoint htpasswd httpd:2.4 -Bbn "$registry_user" "$registry_password" >"$tmp/auth/htpasswd"
docker run -d --restart=always --name "$registry_name" -v "$tmp/auth:/auth:ro" -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=EnvPlane -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -p 5001:5000 registry:2 >/dev/null

cat >"$tmp/kind.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${registry}"]
    endpoint = ["http://${registry_name}:5000"]
EOF
kind create cluster --name "$cluster" --config "$tmp/kind.yaml"
docker network connect kind "$registry_name" >/dev/null 2>&1 || true
kubectl --context "kind-$cluster" apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "${registry}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

docker pull registry.k8s.io/pause:3.10 >/dev/null
docker tag registry.k8s.io/pause:3.10 "$registry/envplane/sm09:1"
printf '%s' "$registry_password" | docker login "$registry" --username "$registry_user" --password-stdin >/dev/null
docker push "$registry/envplane/sm09:1" >/dev/null
docker logout "$registry" >/dev/null

kubectl --context "kind-$cluster" create namespace "$base_namespace"
kubectl --context "kind-$cluster" create namespace "$target_namespace"
kubectl --context "kind-$cluster" -n "$base_namespace" create secret docker-registry registry-source --docker-server="$registry" --docker-username="$registry_user" --docker-password="$registry_password" >/dev/null
kubectl --context "kind-$cluster" -n "$base_namespace" create secret generic application-source --from-literal=config="$application_secret" >/dev/null

values="$tmp/values.yaml"
cp "$(dirname "$0")/../deploy/helm/envplane/values-e2e-local.yaml" "$values"
cat >>"$values" <<EOF
global:
  envplane:
    e2eFixture:
      baseNamespace: $base_namespace
      featureNamespace: $target_namespace
envplane-agent:
  rbac:
    discovery:
      namespaces: [$base_namespace, $target_namespace]
    materialization:
      enabled: true
      items:
        - id: registry
          sourceNamespace: $base_namespace
          sourceName: registry-source
          targetNamespace: $target_namespace
          targetName: registry-pull
        - id: application
          sourceNamespace: $base_namespace
          sourceName: application-source
          targetNamespace: $target_namespace
          targetName: application-config
EOF
helm upgrade --install "$release" "$ENVPLANE_SM09_CHART" --kube-context "kind-$cluster" --namespace "$namespace" --create-namespace --values "$values" --wait --timeout 15m
kubectl --context "kind-$cluster" -n "$namespace" rollout status deployment/envplane-control-plane --timeout=5m
kubectl --context "kind-$cluster" -n "$namespace" rollout status deployment/envplane-agent --timeout=5m

api_port=18080
kubectl --context "kind-$cluster" -n "$namespace" port-forward svc/envplane-control-plane "$api_port:8080" >"$tmp/port-forward.log" 2>&1 & pids+=("$!")
api="http://127.0.0.1:$api_port"
for _ in $(seq 1 90); do curl -fsS "$api/api/v1/health" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "$api/api/v1/health" >/dev/null

# Drive the public Bootstrap API. The payload contains references and bounded
# metadata only; it never contains a Secret value or registry credential.
curl -fsS -X PATCH "$api/api/v1/projects/$project/bootstrap-session" -H 'content-type: application/json' -d "{\"stepData\":{\"secretStrategies\":{\"registry\":{\"strategy\":\"encrypted clone\",\"required\":true,\"serviceId\":\"service/private-image\",\"namespace\":\"$base_namespace\",\"secretName\":\"registry-source\",\"targetName\":\"registry-pull\",\"retentionHours\":24},\"application\":{\"strategy\":\"encrypted clone\",\"required\":true,\"serviceId\":\"service/private-image\",\"namespace\":\"$base_namespace\",\"secretName\":\"application-source\",\"targetName\":\"application-config\",\"retentionHours\":24}}}}" >"$tmp/bootstrap.json"
curl -fsS -X POST "$api/api/v1/projects/$project/bootstrap-session/compile" >"$tmp/compiled.json"
curl -fsS -X POST "$api/api/v1/environments" -H 'content-type: application/json' -d "{\"id\":\"$environment\",\"project_id\":\"$project\",\"cluster_id\":\"local-e2e\",\"namespace\":\"$target_namespace\",\"mode\":\"full\"}" >"$tmp/environment.json"
project_config="$(curl -fsS "$api/api/v1/projects/$project/config")"
plan_id="$(jq -er '.secretMaterializationPlan.planId // .config.secretMaterializationPlan.planId' <<<"$project_config")"

# A private image must fail before its pull credential exists.
kubectl --context "kind-$cluster" -n "$target_namespace" run before-materialization --image="$registry/envplane/sm09:1" --restart=Never >/dev/null
sleep 8
! kubectl --context "kind-$cluster" -n "$target_namespace" get pod before-materialization -o jsonpath='{.status.phase}' | grep -qx Running

# A foreign Secret at an approved target name must never be adopted. This is
# metadata-only and is deleted before the retry below.
kubectl --context "kind-$cluster" -n "$target_namespace" create secret generic registry-pull --from-literal=owner=foreign >/dev/null
curl -fsS -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"materialize\"}" >"$tmp/foreign-dispatch.json"
for _ in $(seq 1 120); do
  status="$(curl -fsS "$api/api/v1/projects/$project/secret-materialization?planId=$plan_id")"
  jq -e '.state == "failed" and (.items[] | select(.id == "registry") | .errorCode == "conflict")' <<<"$status" >/dev/null 2>&1 && break
  sleep 2
done
jq -e '.state == "failed" and (.items[] | select(.id == "registry") | .errorCode == "conflict")' <<<"$status" >/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" delete secret registry-pull >/dev/null

curl -fsS -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"materialize\"}" >"$tmp/dispatch.json"
for _ in $(seq 1 120); do
  status="$(curl -fsS "$api/api/v1/projects/$project/secret-materialization?planId=$plan_id")"
  jq -e '.state == "ready" and (.items | all(.[]; .state == "ready"))' <<<"$status" >/dev/null 2>&1 && break
  sleep 2
done
jq -e '.state == "ready" and (.items | all(.[]; .state == "ready"))' <<<"$status" >/dev/null
! grep -Fq "$registry_password" "$tmp"/*.json "$tmp"/*.log 2>/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" get secret registry-pull >/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" get secret application-config >/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" run after-materialization --image="$registry/envplane/sm09:1" --restart=Never --overrides='{"spec":{"imagePullSecrets":[{"name":"registry-pull"}]}}' >/dev/null
kubectl --context "kind-$cluster" -n "$target_namespace" wait --for=condition=Ready pod/after-materialization --timeout=120s

# Explicit source rotation is a fresh materialization command, never a silent
# mutation. Restarting Agent validates lease/queue recovery before the command.
kubectl --context "kind-$cluster" -n "$namespace" rollout restart deployment/envplane-agent
kubectl --context "kind-$cluster" -n "$namespace" rollout status deployment/envplane-agent --timeout=5m
before_rotation="$(kubectl --context "kind-$cluster" -n "$target_namespace" get secret application-config -o jsonpath='{.metadata.resourceVersion}')"
rotated_application_secret="$(openssl rand -hex 24)"
kubectl --context "kind-$cluster" -n "$base_namespace" delete secret application-source >/dev/null
kubectl --context "kind-$cluster" -n "$base_namespace" create secret generic application-source --from-literal=config="$rotated_application_secret" >/dev/null
curl -fsS -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"materialize\"}" >"$tmp/rotation.json"
for _ in $(seq 1 120); do
  after_rotation="$(kubectl --context "kind-$cluster" -n "$target_namespace" get secret application-config -o jsonpath='{.metadata.resourceVersion}')"
  [[ "$after_rotation" != "$before_rotation" ]] && break
  sleep 2
done
[[ "$after_rotation" != "$before_rotation" ]]
curl -fsS -X POST "$api/api/v1/environments/$environment/secret-materialization/dispatch" -H 'content-type: application/json' -d "{\"planId\":\"$plan_id\",\"operation\":\"cleanup\"}" >"$tmp/cleanup.json"
for _ in $(seq 1 120); do kubectl --context "kind-$cluster" -n "$target_namespace" get secret registry-pull >/dev/null 2>&1 || break; sleep 2; done
! kubectl --context "kind-$cluster" -n "$target_namespace" get secret registry-pull >/dev/null 2>&1
! kubectl --context "kind-$cluster" -n "$target_namespace" get secret application-config >/dev/null 2>&1
echo "SM-09 private-registry lifecycle gate passed"
