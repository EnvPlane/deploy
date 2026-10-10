# Release 0.4.711 regression verification

Date: 2026-10-10, Europe/Berlin. Status: artifact and local regression PASS;
deployment and comprehensive live acceptance PENDING target clarification.

## Verified release

- Anonymous OCI pull succeeded: `ghcr.io/envplane/envplane:0.4.711`, digest
  `sha256:e1e58e8739cb3a26b202f0d9565a66033413f56ea8a43e48d6e71050674f630e`.
- GitHub and OCI chart archives are byte-identical. Signed release index passed
  cosign verification for the main release-on-main workflow and Actions issuer.
- Published chart reinstall compatibility/render check passed.
- Required exact-SHA CI succeeded for API `b04c474`, Runner `6444f5b`, Agent
  `b954691`, frontend `c41bd76`, webhook `da04389`, deploy `7c6caab`.
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
