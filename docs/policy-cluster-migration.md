# Policy-capable cluster migration (administrator workflow)

Status: code and mocked checks only. No existing cluster was migrated. A CNI name
or successful DaemonSet rollout is **not** evidence of traffic enforcement.

## Decision and scope

For the observed bridge/host-local/portmap/firewall installation in
`bethunder-local`, prefer a **new, separately named Minikube profile with Calico**.
Do not run `minikube start --cni=calico` against the existing profile. Keep all
`app-*`, `app2-*`, their PVs and database data on the source until a separately
approved, rehearsed cutover. The tool never deletes/recreates clusters, invokes
SSH, writes node CNI files, changes routes, moves workloads or copies Secrets.

Policy-only kube-router is an alternative **requiring separate compatibility and
host review**. Its v2.5.0 firewall example has router/proxy disabled but an
`install-cni` init container that can replace existing CNI files; applying that
upstream manifest unmodified is unsafe here. No automatic policy-engine install
or privileged cleanup command is provided. Do not layer two networking CNIs.

Primary references reviewed 2026-10-08:

- [Minikube NetworkPolicy prerequisites](https://minikube.sigs.k8s.io/docs/handbook/network_policy/)
- [Minikube explicit CNI selection](https://minikube.sigs.k8s.io/docs/commands/start/)
- [kube-router selective functionality](https://www.kube-router.io/docs/user-guide/)
- [Versioned v2.5.0 firewall manifest](https://github.com/cloudnativelabs/kube-router/blob/v2.5.0/daemonset/kube-router-firewall-daemonset.yaml)

The selected Kubernetes patch must be supported by the administrator's reviewed
Minikube release and bundled Calico version. Record the exact Minikube binary
version, Calico images/digests, driver/runtime and Kubernetes patch in the change
record; this tool does not assert compatibility for an arbitrary version.

## Inventory, backups and dry-run plan

Requires Python 3 standard library, kubectl and Minikube. `inventory` makes only
read calls to the explicit source context; `plan` makes **no cluster calls**.
Use a private directory, exact version and distinct target name chosen by the
administrator. Examples below create local files only:

```sh
python3 scripts/plan-policy-cluster-migration.py inventory \
  --context bethunder-local --out /private/tmp/policy-inventory.json
python3 scripts/plan-policy-cluster-migration.py plan \
  --inventory /private/tmp/policy-inventory.json \
  --target bethunder-policy-candidate --kubernetes-version v1.35.1 \
  --out /private/tmp/policy-plan.json
```

`v1.35.1` is an example, not an approved compatibility claim. Outputs are exclusive
create, mode 0600: existing paths/symlinks are refused. Inventory is a projected
metadata **backup for review, not a workload/database restore backup**. It records
cluster UID, node kernel/runtime/Pod CIDRs, service IPs, endpoint references,
ingress/PVC/PV ownership and existing policy references. It excludes raw manifests,
annotations, environment values, Secrets, kubeconfigs and ConfigMap contents.
Inventory/command errors stop the operation, without echoing credential-plugin
stderr. No empty-on-error inventory is accepted.

Before a migration/cutover, an administrator must additionally capture into
encrypted restricted storage (outside this tool) and rehearse restore of:

- databases (consistent dump/snapshot and integrity verification), PVC/PV data,
  storage/reclaim behavior, manifests from SCM and credentials via the secret manager;
- node CNI files, bridge/IPAM allocation, MTU, Pod/Service CIDRs, routing table,
  iptables/nftables/ipset rules and firewall hooks from approved read-only access;
- ingress/DNS/LB routes, Flux reconciliation, Agent/Runner control-plane paths,
  SCM registry egress and namespaces with nonstandard policy selectors;
- local Docker disk/RAM capacity for both clusters and protection against profile
  name collisions, container/runtime/CIDR overlap and accidental host-port takeover.

No host facts are inferred from CNI image names. The tool marks them as requiring
administrator review. Do not collect plaintext credentials into the change record.

## Explicit creation gate (not executed by this change)

Review the entire JSON and record its canonical SHA256 printed by `plan`. After
separate administrator approval, `apply-new-cluster` creates **only the blank
target profile**, with Docker driver and Calico, `--keep-context` and disabled
interactive prompts. It requires both that SHA256 and
the exact target name, rejects altered plans/inventory, re-reads source inventory
to detect drift, and rejects any existing valid/invalid/stopped profile or kube
context. It does not switch application routes or management credentials.

```sh
python3 scripts/plan-policy-cluster-migration.py apply-new-cluster \
  --plan /private/tmp/policy-plan.json --inventory /private/tmp/policy-inventory.json \
  --reviewed-sha256 REVIEWED_CANONICAL_SHA256 \
  --approve-target bethunder-policy-candidate
```

Do not run concurrently with other profile creation; Minikube itself is responsible
for profile creation locking. On partial failure, leave the candidate untouched,
inspect it, and obtain a recovery decision: the script never automatically deletes
it or restarts an existing profile with a changed CNI. Preserve the source.

## Acceptance and rollback safeguards

Before workload restore or cutover, run the independent Agent NetworkPolicy probe
on the candidate and securely upload its signed/identity-bound evidence through
the API. Then repeat acceptance after restore. Require positive baseline, fresh
HTTP ingress deny, selected-label ingress allow, egress deny, policy removal
recovery, cross-namespace allow/deny and multi-node checks if applicable. Include
TCP/UDP DNS, Kubernetes API, SCM/registry, management endpoint and allowed base
service/Hybrid paths. Test Pod IP and Service IP; include hairpin/SNAT cases.
Only the probe-owned namespace/resources may be cleaned up. Preserve app data.

Restore workloads with an explicit environment ownership/import plan (no duplicate
Flux owners), verify database contents and application health, reconciliation,
preview routes and absence of unexpected policy bypass. Restart nodes and repeat
the deny/allow matrix to verify persistence. Controller Ready is insufficient.

Rollback before cutover: retain original routes and source workloads. Rollback
after cutover requires a rehearsed database write freeze and data reconciliation;
do not point clients at stale source databases. Never delete PVs, remove finalizers,
flush firewall rules or disable isolation as an automated rollback. An in-place
policy engine needs a distinct host-specific rollback that removes only its owned
rules and preserves original firewall/IPAM/routing; not supplied here.

## Zero-setup prevention

`minikube-up.sh` now selects Calico explicitly for **new** profiles and refuses to
restart a stopped/broken existing profile with a new CNI. Running existing profiles
are preserved. This does not claim their policies work; onboarding/readiness must
still require fresh actual traffic evidence. A fresh candidate has no automatic
application import, data restore, license, public tunnel or workload cutover.

Local tests: `python3 -m unittest discover -s scripts/tests -p 'test_policy_cluster_migration.py'`.
These mock all subprocesses and do not access Kubernetes or Minikube.
