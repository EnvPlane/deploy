# Administrator migration acceptance and data-preserving cutover

Status: pending live administrator review; P0 isolation acceptance gate.

Review follow-up fixed: minikube-up.sh previously treated unknown JSON `{}` as an
empty profile inventory. Its inline guard now requires both valid/invalid arrays
and nonempty string profile names; only the explicit empty-array format permits
zero-profile creation. python3 is required before the cluster branch. Regression
tests execute the actual inline guard and verify pipeline errors block creation.
No live cluster creation or network change was performed.

Tooling implemented in scripts/plan-policy-cluster-migration.py and documented in
docs/policy-cluster-migration.md. Existing bethunder-local is unchanged. The safe
default creates a separate Calico candidate; no in-place engine is auto-installed.

## Codex implementation prompt

After separate live administrator authorization, inventory source and review exact
Minikube/Kubernetes/Calico compatibility, routes/IPAM/firewall and encrypted tested
database/PVC backups. Use the hash-gated new-cluster plan, never mutate the existing
profile's CNI. Record artifact digests and run actual ingress/egress deny/allow and
recovery tests. Securely transfer evidence using identity-bound Agent submission.
Restore only explicitly authorized workloads/data, avoiding dual Flux ownership;
verify health, preview routes, DNS/API/SCM/management and Hybrid paths. Rehearse
write-freeze/data reconciliation rollback before any separately approved cutover.
Keep all source app-* and app2-* namespaces and volumes until approved retirement.
No plaintext Secrets/kubeconfigs in reports, no broad prune or node firewall flush.

Acceptance: enforced negative and positive controls persist across restart; data
integrity and application/reconciliation health confirmed; source retained; no
isolation-ready claim from CNI brand/API existence alone. Mocked tooling tests are
not live acceptance. If selecting kube-router policy-only, create a separate pinned
digest configuration/review that excludes CNI-writing init containers and prove
kernel/iptables/ipset compatibility and targeted rollback on a disposable clone
first. The unmodified v2.5.0 firewall manifest is not approved for this source.
