# Live storage cleanup verification

Observed 2026-10-08, completed by 19:11:47 UTC / 21:11:47 Europe/Berlin.
Physical target: bethunder-policy-candidate, single Minikube/containerd node.
No existing application, rollback or authentication PVC was deleted.

## Method

Created only namespace envplane-storage-cleanup-1008-a, two 16Mi PVC requests
and digest-pinned BusyBox Pods. Each wrote and synced the disposable marker
storage-cleanup-20261008. Both claims were Bound; marker content was read inside
the Pods and marker-file existence verified independently on the node.

Recorded exact PVC/PV UID, claim binding, reclaim policy, node and backing path
before deletion. Removed only these Pods and PVCs using UID-preconditioned API
DeleteOptions; waited for normal provisioner PV reclamation. Did not directly
delete PVs, backing paths or finalizers, restart shared controllers, or patch
provisioner identities. Checked both `! -e` and `! -L` on each exact node path.

| Claim / StorageClass | PV | Result |
|---|---|---|
| standard-probe / standard | pvc-1366cb3d-fae2-4c34-a2e1-1eb81445da76 | PVC absent, PV absent, original backing path absent |
| local-path-probe / envplane-local-path | pvc-a16f54a3-6184-4965-a0e7-90ca8db5c8b4 | PVC absent, PV absent, original backing path absent |

Both classes had Delete reclaim; provisioners were k8s.io/minikube-hostpath and
envplane.io/local-path respectively. Local-path used its installed pinned image
sha256:e757967a5ec338f6a9b371c5a9688bedaa8c3578ea3dd4db329ea0084be0a86f.

## Exact data identity

Standard:
- PVC UID: 1366cb3d-fae2-4c34-a2e1-1eb81445da76
- PV UID: f70d22cb-faba-44aa-8a5c-5842e8d5e08f
- Node path: /tmp/hostpath-provisioner/envplane-storage-cleanup-1008-a/standard-probe

Local-path:
- PVC UID: a16f54a3-6184-4965-a0e7-90ca8db5c8b4
- PV UID: 3ce5de27-b29b-4979-83ae-0b6ae1741c38
- Node path: /opt/envplane-local-path/pvc-a16f54a3-6184-4965-a0e7-90ca8db5c8b4_envplane-storage-cleanup-1008-a_local-path-probe

The empty namespace (UID 391f0dc8-e0b3-4d59-ab9c-fc90eb7eea80) was then removed
with a UID precondition. No test Pod/PVC/PV/namespace remains. Protected PV inventory
was compared to its pre-test snapshot: all 9 original names/UIDs/claim bindings and
Bound phases matched exactly. app/backend, app/MySQL and app2/backend remained Ready.

## What passed and what did not become a claim

PASS: normal current-controller reclamation of these two new disposable volumes,
including directory removal, independently of namespace disappearance.

NOT TESTED: a new feature-environment deletion through the UI in this pass,
provisioner/node restart, outage/finalizer recovery, Retain policy, historical
Released volumes, production CSI/backend deletion receipts or snapshot retention.
The old source cluster/PVCs were intentionally untouched for rollback.

NOT PROVEN: forensic secure erase of sectors, Docker disk images, snapshots,
backups or clones. Directory absence is logical disposal of the live mounted
asset, not an assertion about every copy or recoverability of erased blocks.

Kubernetes Delete reclaim removes the PV and supported storage asset; Retain
requires separate manual recovery/cleanup:
https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming

Source cleanup.verified still describes workload/namespace cleanup, not an
independent data-disposal certificate. The existing detail-page warning is correct.

## Reproduction safety prompt

Review the disposable fixture before reuse. Require an absent namespace, no
foreign claims/data under the anticipated standard provisioner namespace path,
record actual identities before deletion and use UID preconditions. Prefer a fresh
unique namespace when repeating. Do not apply the fixture over an existing namespace,
force finalizers, erase directories manually or touch baseline/rollback storage.
