#!/usr/bin/env bash
# Render the target-cluster RBAC profile consumed by envplane's Remote Cluster
# Reconciler. The result contains no credentials and can be reviewed before it
# is applied. Dynamic project namespaces receive workload access only through
# server-owned RoleBindings after ownership verification.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: render-remote-cluster-rbac-profile.sh --cluster-id ID [options]

Options:
  --runtime-namespace NAME   Namespace for the envplane target runtimes (default: envplane-system)
  --managed-namespace NAME   Existing namespace for read-only workload discovery; repeatable
  --deployment-backend NAME  Installation mode: helm-direct (default) or fluxcd
  --flux-control-namespace NAME  Flux control namespace for fluxcd mode (default: flux-system)
  --flux-namespace NAME      Existing namespace that also permits read-only Flux status; repeatable
  --flux-status-reader-namespace NAME  Opt-in installer get-only Kustomization delegation parent; repeatable
  --project-id ID            Include computed Agent binding identities for review; repeatable
  --finops-node-inventory    Opt-in capability get/list nodes for Agent GPU capacity inventory
  --help                     Show this help
EOF
}

cluster_id=""
runtime_namespace="envplane-system"
managed_namespaces=()
flux_namespaces=()
flux_status_namespaces=()
deployment_backend="helm-direct"
flux_control_namespace="flux-system"
project_ids=()
finops_node_inventory=false

require_option_value() {
  local option="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "${2:0:2}" == "--" ]]; then
    echo "$option requires a non-empty value" >&2
    usage >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-id) require_option_value "$@"; cluster_id="$2"; shift 2 ;;
    --runtime-namespace) require_option_value "$@"; runtime_namespace="$2"; shift 2 ;;
    --managed-namespace) require_option_value "$@"; managed_namespaces+=("$2"); shift 2 ;;
    --deployment-backend) require_option_value "$@"; deployment_backend="$2"; shift 2 ;;
    --flux-control-namespace) require_option_value "$@"; flux_control_namespace="$2"; shift 2 ;;
    --flux-namespace) require_option_value "$@"; flux_namespaces+=("$2"); shift 2 ;;
    --flux-status-reader-namespace) require_option_value "$@"; flux_status_namespaces+=("$2"); shift 2 ;;
    --project-id) require_option_value "$@"; project_ids+=("$2"); shift 2 ;;
    --finops-node-inventory) finops_node_inventory=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

dns_label='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
case "$deployment_backend" in
  helm-direct) ;;
  fluxcd)
    # Selecting Flux is the administrator's installation-profile decision.
    # Future environment names need a delegation parent without resourceNames;
    # project Agents still receive only their computed exact-name Roles.
    flux_status_namespaces+=("$flux_control_namespace")
    ;;
  *) echo "deployment backend must be helm-direct or fluxcd" >&2; exit 2 ;;
esac
if [[ ! "$flux_control_namespace" =~ $dns_label ]] || [[ ${#flux_control_namespace} -gt 63 ]]; then
  echo "Flux control namespace must be a Kubernetes DNS label up to 63 characters" >&2
  exit 2
fi
for value in "$cluster_id" "$runtime_namespace"; do
  if [[ ! "$value" =~ $dns_label ]] || [[ ${#value} -gt 63 ]]; then
    echo "cluster ID and namespace names must be Kubernetes DNS labels up to 63 characters" >&2
    exit 2
  fi
done
for project_id in "${project_ids[@]}"; do
  if [[ ! "$project_id" =~ $dns_label ]] || [[ ${#project_id} -gt 63 ]]; then
    echo "project IDs must be Kubernetes DNS labels up to 63 characters" >&2
    exit 2
  fi
done
service_account="envplane-remote-cluster-$cluster_id"
for namespace in "${flux_namespaces[@]}" "${flux_status_namespaces[@]}"; do
  if [[ ! "$namespace" =~ $dns_label ]] || [[ ${#namespace} -gt 63 ]]; then
    echo "Flux namespace names must be Kubernetes DNS labels up to 63 characters" >&2
    exit 2
  fi
done

# Explicit administrator opt-in: resourceNames cannot represent future feature
# names. This get-only parent supports delegation to exact-name Agent Roles.
# It also permits the installer to get other Kustomizations in this namespace.
# Never enable this automatically for existing credentials or non-Flux targets.
validated_flux_status_namespaces=()
for namespace in "${flux_status_namespaces[@]}"; do
  duplicate=false
  for existing in "${validated_flux_status_namespaces[@]}"; do
    [[ "$existing" != "$namespace" ]] || duplicate=true
  done
  [[ "$duplicate" == true ]] || validated_flux_status_namespaces+=("$namespace")
done

prefix="envplane-remote-cluster-$cluster_id"
installer_principal="system:serviceaccount:$runtime_namespace:$service_account"
capability_role="$prefix-cluster-capability-reader"
inventory_role="$prefix-namespace-inventory-reader"
metadata_role="$prefix-namespace-metadata-reader"
all_namespaces=("$runtime_namespace")
unique_managed_namespaces=()
append_unique_managed_namespace() {
  local candidate="$1"
  local existing
  for existing in "${unique_managed_namespaces[@]}"; do
    if [[ "$existing" == "$candidate" ]]; then
      return 0
    fi
  done
  unique_managed_namespaces+=("$candidate")
}
append_unique_namespace() {
  local candidate="$1"
  local existing
  for existing in "${all_namespaces[@]}"; do
    if [[ "$existing" == "$candidate" ]]; then
      return 0
    fi
  done
  all_namespaces+=("$candidate")
}
for namespace in "${managed_namespaces[@]}"; do
  if [[ ! "$namespace" =~ $dns_label ]] || [[ ${#namespace} -gt 63 ]]; then
    echo "managed namespace names must be Kubernetes DNS labels up to 63 characters" >&2
    exit 2
  fi
  append_unique_managed_namespace "$namespace"
  append_unique_namespace "$namespace"
done
managed_namespaces=("${unique_managed_namespaces[@]}")

append_unique_flux_namespace() {
  local candidate="$1"
  local existing
  for existing in "${validated_flux_namespaces[@]}"; do
    if [[ "$existing" == "$candidate" ]]; then
      return 0
    fi
  done
  validated_flux_namespaces+=("$candidate")
}
validated_flux_namespaces=()
for namespace in "${flux_namespaces[@]}"; do
  append_unique_flux_namespace "$namespace"
done

# Reuse the exact-name recovery renderer rather than maintaining a second
# project-release/hash implementation. These identities are review metadata;
# the lifecycle rule below also supports projects created after onboarding.
project_binding_names=()
for project_id in "${project_ids[@]}"; do
  names="$(bash "$(dirname "${BASH_SOURCE[0]}")/render-remote-project-binding-access.sh" \
    --cluster-id "$cluster_id" --project-id "$project_id" --runtime-namespace "$runtime_namespace" \
    | awk '/^      - / {print $2}')"
  while IFS= read -r name; do
    [[ -n "$name" ]] || { echo "project binding derivation failed" >&2; exit 1; }
    duplicate=false
    for existing in "${project_binding_names[@]}"; do
      [[ "$existing" != "$name" ]] || duplicate=true
    done
    [[ "$duplicate" == true ]] || project_binding_names+=("$name")
  done <<<"$names"
done
reviewed_bindings="$(IFS=,; printf '%s' "${project_binding_names[*]}")"

cat <<EOF
# Generated by scripts/render-remote-cluster-rbac-profile.sh.
# Review this file before applying it. It intentionally contains no token,
# kubeconfig or other credential material.
apiVersion: v1
kind: Namespace
metadata:
  name: $runtime_namespace
  labels:
    app.kubernetes.io/part-of: envplane
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: ServiceAccount
automountServiceAccountToken: false
metadata:
  name: $service_account
  namespace: $runtime_namespace
  labels:
    app.kubernetes.io/part-of: envplane
    envplane.io/owner: local-platform
    envplane.io/remote-cluster-id: $cluster_id
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $prefix-installer
  annotations:
    envplane.io/access-profile: "dynamic-project-bindings-v1"
    envplane.io/reviewed-project-bindings: "$reviewed_bindings"
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "create", "delete"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterrolebindings"]
    # RBAC cannot authorize a name prefix or future resourceNames. GET also
    # exposes unrelated binding metadata (not Secret data); admission controls
    # only writes. Review this tradeoff once, before connecting the cluster.
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterroles"]
    resourceNames:
      - $prefix-cluster-capability-reader
      - $prefix-namespace-inventory-reader
      - $prefix-namespace-metadata-reader
      - $prefix-rbac-manager
      - $prefix-discovery-parent
      - $prefix-feature-env-writer-parent
    verbs: ["bind"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterroles"]
    resourceNames:
      - $prefix-namespace-metadata-reader
    verbs: ["get", "update", "patch"]
  # Kubernetes RBAC cannot constrain create by resource name. The companion
  # ValidatingAdmissionPolicy below therefore permits these verbs only for a
  # Helm-owned Runner namespace-reader with the exact bounded rule shape.
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterroles"]
    verbs: ["create", "get", "update", "patch", "delete"]
  # The bind verb is evaluated by Kubernetes independently of admission. The
  # admission policy below constrains every corresponding ClusterRoleBinding
  # to a Helm-owned Runner namespace-reader with one local ServiceAccount.
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["clusterroles"]
    verbs: ["bind"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $prefix-installer
subjects:
  - kind: ServiceAccount
    name: $service_account
    namespace: $runtime_namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $prefix-installer
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: $prefix-installer-clusterrole-scope
spec:
  failurePolicy: Fail
  matchConstraints:
    matchPolicy: Equivalent
    namespaceSelector: {}
    objectSelector: {}
    resourceRules:
      - apiGroups: ["rbac.authorization.k8s.io"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE", "DELETE"]
        resources: ["clusterroles"]
        scope: "*"
  validations:
    - expression: >-
        request.userInfo.username != "$installer_principal" ||
        (request.operation == "DELETE" ?
          (oldObject.metadata.name.matches('^ep-runner-[a-z0-9-]+-envplane-runner-feature-env-namespace-reader$') &&
           oldObject.metadata.labels['app.kubernetes.io/managed-by'] == "Helm" &&
           oldObject.metadata.labels['app.kubernetes.io/name'] == "envplane-runner" &&
           oldObject.metadata.annotations['meta.helm.sh/release-name'] == oldObject.metadata.labels['app.kubernetes.io/instance'] &&
           oldObject.metadata.annotations['meta.helm.sh/release-namespace'] == "$runtime_namespace")
          :
          (object.metadata.name == "$prefix-namespace-metadata-reader" ||
           (object.metadata.name.matches('^ep-runner-[a-z0-9-]+-envplane-runner-feature-env-namespace-reader$') &&
           object.metadata.labels['app.kubernetes.io/managed-by'] == "Helm" &&
           object.metadata.labels['app.kubernetes.io/name'] == "envplane-runner" &&
           object.metadata.annotations['meta.helm.sh/release-name'] == object.metadata.labels['app.kubernetes.io/instance'] &&
           object.metadata.annotations['meta.helm.sh/release-namespace'] == "$runtime_namespace" &&
           object.rules.size() == 1 &&
           object.rules[0].apiGroups == [""] &&
           object.rules[0].resources == ["namespaces"] &&
           object.rules[0].verbs.size() >= 1 &&
           object.rules[0].verbs.all(verb, verb == "get" || verb == "delete") &&
           object.rules[0].verbs.exists(verb, verb == "get") &&
           object.rules[0].resourceNames.size() >= 1 &&
           object.rules[0].resourceNames.all(name, name.matches('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')))))
      message: "remote installer may manage only bounded Helm-owned Runner namespace-reader ClusterRoles"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: $prefix-installer-clusterrole-scope
spec:
  policyName: $prefix-installer-clusterrole-scope
  validationActions: ["Deny"]
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: $prefix-installer-clusterrolebinding-scope
spec:
  failurePolicy: Fail
  matchConstraints:
    matchPolicy: Equivalent
    namespaceSelector: {}
    objectSelector: {}
    resourceRules:
      - apiGroups: ["rbac.authorization.k8s.io"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE", "DELETE"]
        resources: ["clusterrolebindings"]
        scope: "*"
  validations:
    - expression: >-
        request.userInfo.username != "$installer_principal" ||
        (request.operation == "DELETE"
          ? ((["$capability_role", "$inventory_role", "$metadata_role"].exists(name, name == oldObject.roleRef.name)) ||
              (oldObject.metadata.name.matches('^ep-agent-[a-z0-9-]+-envplane-agent-cluster-capability-reader$') &&
               oldObject.roleRef.name == oldObject.metadata.name &&
               oldObject.subjects.exists(subject, subject.kind == "ServiceAccount" && subject.namespace == "$runtime_namespace")) ||
              (oldObject.metadata.name.matches('^ep-runner-[a-z0-9-]+-envplane-runner-feature-env-namespace-reader$') &&
               oldObject.roleRef.name == oldObject.metadata.name &&
               oldObject.subjects.size() == 1 &&
               oldObject.subjects[0].kind == "ServiceAccount" &&
               oldObject.subjects[0].namespace == "$runtime_namespace")) &&
            oldObject.metadata.labels['app.kubernetes.io/managed-by'] == "Helm" &&
            ((oldObject.metadata.labels['app.kubernetes.io/component'] == "cluster-agent" &&
              oldObject.metadata.labels['app.kubernetes.io/name'] == "envplane-agent") ||
             oldObject.metadata.labels['app.kubernetes.io/name'] == "envplane-runner")
          : (["$capability_role", "$inventory_role", "$metadata_role"].exists(name, name == object.roleRef.name) ||
             (object.metadata.name.matches('^ep-runner-[a-z0-9-]+-envplane-runner-feature-env-namespace-reader$') &&
              object.roleRef.name == object.metadata.name &&
              object.subjects.size() == 1 &&
              object.subjects[0].kind == "ServiceAccount" &&
              object.subjects[0].namespace == "$runtime_namespace" &&
              object.metadata.labels['app.kubernetes.io/name'] == "envplane-runner")) &&
            object.metadata.labels['app.kubernetes.io/managed-by'] == "Helm" &&
            ((object.metadata.labels['app.kubernetes.io/component'] == "cluster-agent") ||
             object.metadata.labels['app.kubernetes.io/name'] == "envplane-runner"))
      message: "remote installer may bind only fixed capability roles or bounded Helm-owned Runner namespace readers"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: $prefix-installer-clusterrolebinding-scope
spec:
  policyName: $prefix-installer-clusterrolebinding-scope
  validationActions: ["Deny"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $prefix-cluster-capability-reader
rules:
EOF
if [[ "$finops_node_inventory" == true ]]; then
  cat <<EOF
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
EOF
fi
cat <<EOF
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingressclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $prefix-namespace-inventory-reader
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $prefix-namespace-metadata-reader
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    resourceNames:
EOF
for namespace in "${all_namespaces[@]}"; do
  printf '      - %s\n' "$namespace"
done
cat <<EOF
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $prefix-rbac-manager
rules:
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $prefix-discovery-parent
rules:
  - apiGroups: ["metrics.k8s.io"]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["services", "configmaps", "resourcequotas", "limitranges", "persistentvolumeclaims", "serviceaccounts", "pods", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "daemonsets", "statefulsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $prefix-feature-env-writer-parent
rules:
  - apiGroups: [""]
    resources: ["configmaps", "events", "services", "resourcequotas", "limitranges", "persistentvolumeclaims", "secrets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "replicasets", "daemonsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

cat <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $prefix-runtime-manager
  namespace: $runtime_namespace
rules:
  - apiGroups: [""]
    resources: ["configmaps", "events", "persistentvolumeclaims", "pods", "secrets", "serviceaccounts", "services"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $prefix-runtime-manager
  namespace: $runtime_namespace
subjects:
  - kind: ServiceAccount
    name: $service_account
    namespace: $runtime_namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $prefix-runtime-manager
EOF

for namespace in "${managed_namespaces[@]}"; do
  [[ "$namespace" == "$runtime_namespace" ]] && continue
  cat <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $prefix-discovery-reader
  namespace: $namespace
rules:
  - apiGroups: ["metrics.k8s.io"]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["configmaps", "events", "persistentvolumeclaims", "serviceaccounts", "services", "pods", "resourcequotas", "limitranges"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $prefix-discovery-reader
  namespace: $namespace
subjects:
  - kind: ServiceAccount
    name: $service_account
    namespace: $runtime_namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $prefix-discovery-reader
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $prefix-discovery-parent
  namespace: $namespace
subjects:
  - kind: ServiceAccount
    name: $service_account
    namespace: $runtime_namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $prefix-discovery-parent
EOF
done

for namespace in "${validated_flux_namespaces[@]}"; do
  cat <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $prefix-flux-reader
  namespace: $namespace
rules:
  - apiGroups: ["kustomize.toolkit.fluxcd.io"]
    resources: ["kustomizations"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["helm.toolkit.fluxcd.io"]
    resources: ["helmreleases"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["source.toolkit.fluxcd.io"]
    resources: ["gitrepositories", "helmrepositories", "ocirepositories", "buckets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $prefix-flux-reader
  namespace: $namespace
subjects:
  - kind: ServiceAccount
    name: $service_account
    namespace: $runtime_namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $prefix-flux-reader
EOF
done

for namespace in "${validated_flux_status_namespaces[@]}"; do
  cat <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $prefix-flux-status-parent
  namespace: $namespace
  annotations:
    envplane.io/access-profile: dynamic-flux-status-get-v1
rules:
  - apiGroups: ["kustomize.toolkit.fluxcd.io"]
    resources: ["kustomizations"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $prefix-flux-status-parent
  namespace: $namespace
subjects:
  - kind: ServiceAccount
    name: $service_account
    namespace: $runtime_namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $prefix-flux-status-parent
EOF
done
