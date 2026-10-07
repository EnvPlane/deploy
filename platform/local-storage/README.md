# Restart-safe local feature storage

This administrator-installed, opt-in storage profile fixes Minikube hostpath
reclaim failures across provisioner restarts. It is for disposable single-node
local development clusters, not highly available production storage.

The built-in Minikube provisioner records a random process identity on each PV
and refuses to delete volumes owned by an earlier process identity:
[upstream implementation](https://github.com/kubernetes/minikube/blob/master/pkg/storage/storage_provisioner.go),
[upstream issue](https://github.com/kubernetes/minikube/issues/16140).
Do not work around this by removing finalizers or adopting old PV identities.

## Install

Prerequisites: administrator access to the intended local cluster, an approved
host path `/opt/envplane-local-path`, and registry access for the pinned images.
Review `local-path.yaml`, especially its RBAC and hostPath helper scripts.

```sh
kubectl --context bethunder-local apply -f platform/local-storage/local-path.yaml
kubectl --context bethunder-local -n envplane-local-path-storage rollout status deployment/local-path-provisioner --timeout=120s
kubectl --context bethunder-local get storageclass standard envplane-local-path
```

The manifest adapts the official Rancher local-path-provisioner v0.0.37
[release](https://github.com/rancher/local-path-provisioner/releases/tag/v0.0.37)
with immutable provisioner/helper image digests, a dedicated namespace and
ServiceAccount, provisioner identity `envplane.io/local-path`, bounded CPU/memory,
and guarded helper paths. It is intentionally NOT installed by project Agents
or the umbrella chart. The helper needs node filesystem access; project runtime
does not receive the provisioner's cluster-wide PV privileges.

`envplane-local-path` is non-default, uses `Delete` reclaim and
`WaitForFirstConsumer`, and creates PV-specific directories. Keep the existing
default StorageClass and Bound/base PVCs unchanged. In the Bootstrap template
editor, explicitly set `spec.storageClassName: envplane-local-path` only on
future feature PVC templates, save, reload to verify each file, then Compile.
Changing only the cluster default cannot override an explicit `standard` class.
Compiled templates affect future provisioning, not existing PVCs.

Local-path does not enforce PVC capacity limits and provides neither replication
nor backups. Choose a production CSI storage provider for production workloads.

## Restart/reclaim acceptance test

Only use the provided disposable fixture if its namespace does not already
contain someone else's resources. Record the dynamically allocated PV name
and backing path before deletion; do not infer a path from a namespace alone.

```sh
kubectl --context bethunder-local apply -f platform/local-storage/reclaim-smoke.yaml
kubectl --context bethunder-local -n envplane-storage-reclaim-test wait --for=condition=Ready pod/restart-probe --timeout=120s
kubectl --context bethunder-local -n envplane-storage-reclaim-test get pvc restart-probe -o yaml
kubectl --context bethunder-local -n envplane-local-path-storage rollout restart deployment/local-path-provisioner
kubectl --context bethunder-local -n envplane-local-path-storage rollout status deployment/local-path-provisioner --timeout=120s
kubectl --context bethunder-local -n envplane-storage-reclaim-test exec restart-probe -- cat /data/reclaim-probe
kubectl --context bethunder-local -n envplane-storage-reclaim-test delete pod restart-probe --wait=true --timeout=120s
kubectl --context bethunder-local -n envplane-storage-reclaim-test delete pvc restart-probe --wait=true --timeout=120s
```

Require all three: marker survived restart, the recorded PV is deleted, and
the recorded PV-specific backing path is absent on its node. Then delete the
empty fixture namespace. Never force-remove finalizers to make this test pass.
If cleanup fails, preserve PV metadata and provisioner logs for investigation.

## Historical volumes and rollback

This controller does not adopt or clean foreign `k8s.io/minikube-hostpath` PVs.
For historical Released PVs, independently verify exact PV/claim UID,
Released/Delete state, no active matching claim, and absence of the backing
path (including dangling symlinks). Only then may an administrator delete a
specifically approved orphan metadata object with a UID precondition. Retain,
unknown ownership, or existing data requires a separate recovery decision.

To roll back, change future templates to an approved class and Compile. Do not
uninstall this controller or remove its namespace/root while it owns any PVs.
Do not delete Bound volumes to move them between storage classes.

## Verified October 7, 2026

On `bethunder-local`, a fresh PVC became Bound, retained its `reclaim-probe`
marker across the controller restart, then its PV and backing directory were
removed after PVC deletion. The fixture namespace was removed. Both future
`app` feature templates (`backend-data`, `mysql-data`) were saved/reloaded and
compiled as configuration v5. Existing base PVCs remained Bound on `standard`
and the backend/MySQL/frontend Pods remained Running and Ready.

Only two approved historical orphan metadata objects were removed with UID
preconditions after their paths were proven already absent:
`pvc-658150bc-fef4-4a99-8d01-1707c4ccddec` and
`pvc-fdb0a45a-feab-4e62-9688-55ea2f2bc24a`. No backing data or finalizers were
manually removed. Other historical PVs remain outside this remediation scope.
