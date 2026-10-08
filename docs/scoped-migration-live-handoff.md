# Candidate preparation and exact coordinated next phase

2026-10-08. Candidate context bethunder-policy-candidate. Source bethunder-local.
No source freeze, data export, auth transfer or route/management mutation executed
by this worker. Parent owns final live transfer/cutover and exact policy repair.

## Actual candidate preparation

- Ingress envplane-ingress-nginx chart4.11.0 / controller1.11.0, 1/1 Ready.
  ClusterIP service only; no hostNetwork/hostPort/LB/tunnel. This old matching
  source version is fixture compatibility only, not production endorsement.
  Official ingress-nginx retirement: https://kubernetes.github.io/ingress-nginx/
- Flux2.9.5: source1.9.5, kustomize1.9.5, helm1.6.4, notification1.9.4;
  all 1/1 Ready. No candidate GitRepository/Kustomization or SCM credential created.
  https://github.com/fluxcd/flux2/releases/tag/v2.9.5
- Repo pinned local-path provisioner 1/1 Ready, envplane-local-path Class created.
- Exact5 app +6 auth PVCs created, **all Bound**, plus eleven data-helper Pods.
  Candidate app/runtime workloads have not been created or started by this worker.
- Source cached backend/frontend/MySQL/local-Agent images imported into candidate;
  exact published ghcr Agent and Runner digests subsequently pulled successfully.
  Verify usable CRI image identity, not just ctr content presence, before starting.
- Parent handles metrics-server; this worker did not enable it.

## Private paths and gates

- Five-PVC plan /private/tmp/bethunder-five-pvc-plan-20261008.json,
  SHA256 093d8365aacb837838a9d5875335767979e5dedb8425f3196a3510bd216ba48f.
- Six-auth-PVC plan /private/tmp/bethunder-auth-pvc-plan-20261008.json,
  SHA256 6964b94412c1c9480628d91c76d5df0f625d68c887139a33851d7f4c65c0fbe4.
- Private root /private/tmp/envplane-scoped-restore.b8kfrU mode0700;
  identity.agekey mode0600. No data archives yet. Parent may use its separately
  generated age root/key; do not mix decryption identities/artifact ledgers.
- Generated apply-ready List: root/candidate-eleven-pvc-helpers.json (already
  applied to candidate). Contains namespaces, fresh PVCs, helper Pods only;
  no source PVs/history, plaintext tokens or app guessed chart values.

**Current blocker before freeze:** eleven helpers Pending/CreateContainerError.
Docker-save/ctr import produced a synthetic import image name that CRI cannot
resolve. Parent is preparing official fixed Python3.12 Alpine helper digest; set
that reviewed digest on these helper Pods using a controlled replacement (Pods'
image fields can be updated), load/pull through CRI-compatible tooling and require
all helpers Ready plus working tar/Python3 before any source write freeze. Do not
declare image cache presence equal to a successful usable helper. The cold-copy
path is the relevant one: source MYSQL_RANDOM_ROOT_PASSWORD is enabled and no
MYSQL_ROOT_PASSWORD env exists. Logical root dump modes do not apply to this fixture.

Parent now supplies official Python3.12 Alpine digest
sha256:1b668429b3511ab407d8e00648891631b0b1a4d7e15e3ca70f38ab5b91ad4ab4
and age recipient age1cffdcf7vkrsxcw95knx9pf20f945rew03e8zphp7jse0255t6afq93fdqj.
Use the parent's decryption key, not this worker's unused key.
Source envplane-system enforces Restricted PSA: do not apply default root helpers
there or change PSA labels. Render a helper using explicit --helper-uid/--helper-gid
matching verified file ownership, seccomp RuntimeDefault, dropped capabilities,
no privilege escalation, no fsGroup (avoids source-volume ownership mutation).
Such a nonroot helper cannot restore foreign/root ownership; prefer parent's
administrative **read-only cold tar** from the exact current auth PV paths and
candidate-only root restore into exact fresh bound PV directories. Obtain paths
through the exact PVC->PV binding, validate UID and approved namespace again, no
globs/Released PVs, no source chown/SSH writes, no broad privileged Pod or PSA bypass.
This worker does not execute that node-admin transfer or pause source runtimes.

## Exact source freeze commands — parent only, after preflight Ready

Review the full shared Flux-root scope and retain original replicas/suspend flags
from the private plans. These commands are recorded, **not run here**:

```sh
kubectl --context bethunder-local -n flux-system patch kustomization envplane-prs --type merge -p '{"spec":{"suspend":true}}'
kubectl --context bethunder-local -n flux-system patch kustomization e2e-ui-full-652-1007652.generic --type merge -p '{"spec":{"suspend":true}}'
kubectl --context bethunder-local -n app-backend scale deployment/backend --replicas=0
kubectl --context bethunder-local -n app-frontend scale deployment/frontend --replicas=0
kubectl --context bethunder-local -n app2-backend scale deployment/backend --replicas=0
kubectl --context bethunder-local -n app2-frontend scale deployment/frontend --replicas=0
kubectl --context bethunder-local -n envplane-pr-e2e-ui-full-652-1007652 scale deployment/backend deployment/frontend --replicas=0
kubectl --context bethunder-local -n app-backend scale statefulset/mysql --replicas=0
kubectl --context bethunder-local -n envplane-pr-e2e-ui-full-652-1007652 scale statefulset/mysql --replicas=0
kubectl --context bethunder-local -n envplane-system scale deployment/envplane-agent deployment/envplane-runner deployment/ep-agent-c05a23617cac-envplane-agent deployment/ep-runner-c624ad3a794b-envplane-runner --replicas=0
```

Wait until all writers/terminating Pods release claims. Render source read-only
helper Pods from the exact plan, apply only those after the parent freeze, then
backup-pvc all5+6 claims with explicit plan hashes/age recipient. Record archive
SHA256, restore into empty candidate helpers, compare content/metadata checksums.
No runtime may start on candidate while source counterpart is active. Do not
copy all324 old PVs or source kube-system/cluster routes.

## Reviewed private projected live-config snapshot

SCM has only demo namespaces and cannot recreate the current base fixtures.
Parent explicitly authorized a private projected live snapshot of the six scoped
namespaces. Parent must stream source JSON through projection and age encryption
without plaintext host files or tool-output printing. For each exact namespace,
capture Deployments/StatefulSets, Services, Ingresses, ConfigMaps, NetworkPolicies,
ServiceAccounts and namespace Roles/RoleBindings. Preserve actual image/env refs,
labels, selectors and policies; record source Pod imageIDs and pin usable matching
candidate artifact digests. Never invent app2 MySQL or frontend values.

Projection before target apply: strip status; metadata UID/resourceVersion,
managedFields/ownerReferences/creationTimestamp/generation; remove kubectl
last-applied annotations. Force app/runtime replicas0 and CronJob suspend=true.
Remove Service clusterIP/clusterIPs/IP-family/nodePort allocations except headless
clusterIP None; remove autogenerated SA token refs and projected kube-api-access
Pod artifacts. Do not export source Pods/Jobs/Endpoints/PVs or transient controller
objects as deployable definitions. Preserve required Helm ownership annotations.

Export only Secrets explicitly referenced by active approved workloads into age
encryption, never stdout/plaintext files; skip autogenerated service-account-token
Secrets. For Helm ownership, capture **only current latest deployed revision for
each exact active owning release**, never all release history. Parent reviews
cross-namespace hooks, embedded old CA/registration values and cluster-scoped
objects before replay. No raw kubeconfig import/direct management DB edits.

Parent applies reviewed projected candidate workloads paused, restores their
private referenced Secrets, verifies cold MySQL startup/schema/rows and file
checksums, applies the scoped same-namespace feature egress rule and checks actual
Flux reconcile/restart persistence. Deny-all remains; no extra broad allow policy.
Management Save/Put credentials, gateway backend, TLSserverName and final routes
remain exclusively parent-owned. Do not route back to stale source after new writes.
