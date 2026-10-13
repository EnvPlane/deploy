# Cluster prerequisites for envplane

envplane installs into an **existing management Kubernetes cluster**. The
default path is one immutable umbrella Helm release; it does not create a
cluster or install platform controllers. A remote workload cluster is connected
after the management installation through the authenticated UI/API.

## Required for the default installation

| Capability | Requirement | Read-only check |
| --- | --- | --- |
| Kubernetes API | Supported Kubernetes 1.26+ cluster, reachable through the intended kube context, with Ready nodes. | `kubectl --context <context> version` and `kubectl --context <context> get nodes` |
| Helm client | Helm 3.14+ on the operator's workstation. Use the exact signed stable chart version, not `latest`. | `helm version --short` |
| Pod networking and DNS | Working CNI and cluster DNS, commonly CoreDNS, so Pods can reach in-cluster services and resolve Service names. | `kubectl --context <context> -n kube-system get pods` |
| Persistent storage | A default StorageClass that dynamically provisions PVC-backed data for the bundled PostgreSQL and Redis. An explicit existing class requires reviewed operator values instead of the zero-values path. | `kubectl --context <context> get storageclass` |
| Helm permissions | The caller can create the release namespace, chart workloads and namespaced RBAC, and required cluster-scoped RBAC. The preflight reports missing create/list permissions without reading Secret contents. | Run the preflight below. |
| Registry connectivity | The workstation can pull the public OCI chart anonymously from `ghcr.io`; cluster nodes can pull its public images. | Preflight checks the chart pull; confirm image pulls during a disposable installation. |

Use a dedicated context and check its target before running Helm. The optional
preflight covers API reachability, the default StorageClass, the caller's
required RBAC and anonymous chart access for the **default** path:

```bash
scripts/envplane-install-preflight.sh \
  --version <signed-stable-version> \
  --namespace envplane \
  --kube-context <management-context> \
  --output /dev/null
```

The script creates no Kubernetes resources and reads no Secret data. It does
not prove Ready nodes, working Pod networking or DNS, image pulls by nodes,
PVC binding, capacity, or application health. Validate those separately in
the selected cluster. No universal CPU/RAM minimum is published for all
topologies: reserve capacity for the selected chart and its stateful services,
then verify actual Pod scheduling and resource use. The 4 CPU / 6 GiB local
Minikube profile is a test setup, not a production sizing recommendation.

## Capabilities needed for selected features

The basic first-run UI can be reached with a local port-forward. For a stable
public API/UI or SCM webhook endpoint, provide a platform-owned Ingress or
Gateway implementation, suitable DNS, a TLS certificate and reachable network
entry point. A Gateway route also needs Gateway API CRDs and an existing
Gateway. Cloud load balancers and public certificate issuers are the cluster
operator's responsibility. Configure only the capabilities you actually use.

Resource-metrics features need a working metrics API, commonly supplied by
metrics-server. Policy enforcement needs a CNI that implements Kubernetes
NetworkPolicy; an installed policy object alone is not proof of enforcement.
FluxCD is optional for the default Helm installation and required only when a
selected GitOps workflow uses it. envplane does not install Flux, a DNS
controller, cert-manager, a CSI driver, an ingress controller, or a cloud
integration as a side effect of the default install. See the
[platform dependency contract](platform-dependency-contract.md) for explicit
provider ownership and modes.

## Production and remote-cluster planning

Before production use, review durable storage or external data services,
database/PVC backups and tested restore, multi-node availability, policy
enforcement, public endpoint/TLS ownership and the cluster's capacity and
failure domains. A successful single-node Minikube install cannot establish
those guarantees. Follow [advanced installation](installation-advanced.md)
for non-default topology.

For a remote target, install envplane in the management cluster first. The
target needs its own reachable Kubernetes API, scoped installer access,
Pod-to-management HTTPS connectivity and the capabilities required by its
workloads. Prepare the target profile and endpoint according to
[remote clusters](remote-clusters.md); do not treat the management-cluster
preflight as proof of remote readiness.
