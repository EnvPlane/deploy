# Release 0.4.711 regression verification

Date: 2026-10-10, Europe/Berlin. Status: artifact/local regression, kind upgrade,
old application retirement and scoped UI smoke PASS. Comprehensive live lifecycle
acceptance remains pending the source-access, SCM and NetworkPolicy prerequisites.

## Verified release

- Anonymous OCI pull succeeded: `ghcr.io/envplane/envplane:0.4.711`, digest
  `sha256:e1e58e8739cb3a26b202f0d9565a66033413f56ea8a43e48d6e71050674f630e`.
- GitHub and OCI chart archives are byte-identical. Signed release index passed
  cosign verification for the main release-on-main workflow and Actions issuer.
- Published chart reinstall compatibility/render check passed.
- Required exact-SHA CI succeeded for API `b04c474`, Runner `6444f5b`, Agent
  `b954691`, frontend `c41bd76`, webhook `da04389`, deploy `7c6caab`.
- Separately pinned platform-reconciler source `5370087` also passed its exact
  deploy/helm CI, run 38083609695. Publication success was not used as a substitute.
- Agent's newer checkout `770b8e6` differs from the pinned runtime only in CI,
  publication scripts, reviewed module evidence and tickets, not Agent runtime.
  The component publisher change is not deployed Agent functionality.

## Repeated local checks

| Area | Result | Scope |
| --- | --- | --- |
| Frontend | PASS | 504 unit tests, zero skipped/failed; typecheck and lint |
| API/schema | PASS | 9 snapshot, 13 updater and 11 parity regression tests; canonical route parity including no-ripgrep run |
| Runner | PASS | Uncached race tests for pvccopy, mysqlcopy, runner and orchestrator |
| API/runtime | PASS | Uncached race tests for server with HTTP fixtures enabled, pvccopyonboarding, finops, storagecleanup, ai and quota |
| Agent | PASS | Complete uncached race suite, including scanner and DB recovery profile |
| Issuer | PASS | Complete uncached race unit suite; independent component, not umbrella-contained; no live payment |
| Helm | PASS | All seven chart test package groups, uncached; checkout chart contracts, not a fresh install |

Source-based tests do not prove fresh production storage erasure, real external AI
responses, Stripe recovery, SCM webhook delivery or native copy via the deployed
API lease/UI path. Earlier native SQL copy acceptance is separate historical evidence.
No new product defect was reproduced in these checks.

## Installed-target mismatch and safety

The Minikube context `envplane` still has umbrella 0.4.687, revision 40 and
Kubernetes v1.35.1. The open Chrome `envplane.local` Bootstrap screen belongs to
the separate clean kind installation, umbrella 0.4.705 revision 11, Kubernetes
v1.37.0, with test-app-base and Traefik. Their versions must not be conflated.

The user approved upgrading the originally identified test installation. On
discovering the different UI target, deployment was held and clarification was
requested: update the open kind installation instead, both, or original Minikube.
No Helm upgrade, settings mutation, application deletion or PVC mutation occurred.

Private values, manifests and an old-install database dump were captured outside
the repository. The old backup procedure was interrupted before completion and
must not be treated as a validated rollback backup. No credentials or raw dump
contents are included here. A new validated backup is required for the chosen target.

The existing Chrome session is authenticated. Bootstrap preserves copy choices
and blocks compilation on unavailable copy, SCM and fresh NetworkPolicy evidence
in its current older installation. This is a baseline, not a 0.4.711 UI result.
The subsequent browser navigation timed out; no FinOps live PASS is claimed.

## Next live gates

1. Resolve target, create validated private DB/values/manifests backups and use
   `upgrade-umbrella.sh` with complete operator values and reset defaults, not reuse-values.
2. Match running digests and served OpenAPI to 0.4.711, verify rollout and retained settings.
3. Fresh management and remote onboarding, arbitrary Flux names and source-profile review.
4. Consistent MySQL/PVC copy with independent credentials through the actual API lifecycle.
5. Ready, Recreate, delete, Terminated history deletion and refresh; captured-volume cleanup evidence.
6. Real SCM delivery, Hybrid routes, nonempty FinOps, effective NetworkPolicy,
   external AI/fallback and separately authorized sandbox billing recovery.

Overall: not a claim that every historical ticket or production-readiness gate is closed.

## Authorized kind upgrade and old-install retirement

The user explicitly selected kind 0.4.705 for upgrade and requested removal of
the old 0.4.687 application. Kind is now deployed 0.4.711, Helm revision 12.
API/frontend/PostgreSQL/Redis Pods are Ready with zero restarts at observation.
Running image digests match the release pins. Non-Helm Secret data hashes and
all original namespace PVC UIDs/backing-volume identities are unchanged.
Test-app backend/frontend/MySQL Pods and its two base PVCs remain Ready/Bound.

Custom-format PostgreSQL backups of both installations were generated inside
their existing database Pods, passed pg_restore --list, and matched the transferred
archive SHA-256. This validates archive structure and byte transfer, not a full
disaster-recovery restore drill. Complete values/manifests and private Secret
rollback material are retained outside the repository. The original interrupted
backup was superseded by this complete verified old-install archive.

Old releases envplane, ep-agent-ece91a52b07f and ep-runner-962bba4c4f3a were
uninstalled in the exact old context. Its envplane/envplane-executors namespaces,
PVCs, nine PVs and all nine recorded backing directories are absent. Helm-owned
old product ClusterRoles/Bindings are absent. Seven Released/Delete PVs initially
survived due to obsolete Minikube provisioner identity. After claim absence,
retired ownership, policy and path validation, an administrator changed only
those seven identity annotations using JSON Patch state/identity tests. The active
provisioner then removed both volumes and backing directories. No blanket host-path
deletion, finalizer bypass, kind PVC mutation or client-cluster cleanup was used.
Directory absence is ordinary provider deletion, NOT forensic secure erase; the
intentional private backups still exist.

The old Minikube profile was NOT deleted: its ingress-nginx/tunnel temporarily
provides the envplane.local edge route. The relay was moved to ingress-nginx
namespace so it no longer depends on a deleted product namespace. Local frontend
port-forward ended when the selected Pod rolled during upgrade; it was restarted
on localhost only. Domain HTTP 200 and served OpenAPI SHA-256
`d726e2c238e6085a5ff9a4f7eb093ab68e90f21ac3a92e09e3e7e5941d94ee86`
now match canonical reviewed contracts. Independent durable kind-local domain
routing is tracked separately; do not mistake retained edge infrastructure for
a still-running 0.4.687 application.

## Post-upgrade Chrome checks

- Existing owner session and test-app Bootstrap progress survive reload.
- New PVC/MySQL source-profile UI loads; missing configuration returns actionable
  pending review, not a route-parity/API-token error. Copy choices remain preserved
  and do not silently become empty volumes.
- FinOps currency/pricing/infrastructure/telemetry screens load without read error.
  This clean installation has no pricing versions, reconciled report or measured
  source windows: these remain UNKNOWN, not invented zero-consumption evidence.
- Preview `hybrid web with TTL 48 hours` returns valid deterministic fallback,
  Hybrid and TTL 48. No proposal values were applied and no configuration saved.
  Screenshot is private local evidence, not an external-provider AI result.
- Focused UI smoke usability: 4/5; forms and explicit provenance are usable, but
  readiness prerequisites and local domain-forwarding recovery still need setup.

Remaining: reviewed MySQL TLS/backup/source-policy references, compiled Bootstrap,
verified SCM delivery and fresh CNI enforcement before feature lifecycle/copy.
Real Anthropic, remote onboarding, Stripe sandbox recovery and new live storage
erase acceptance are not marked passed by these smoke checks.
