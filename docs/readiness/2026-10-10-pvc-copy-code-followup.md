# PVC data-copy safety and UI follow-up

Installed test candidate remains 0.4.698, revision 10. The user's copy intent for backend-data/mysql-data is preserved. No infrastructure, source PVC, workload, data or authentication change was performed in this code iteration.

## Corrected defects

- API copy refusal previously checked only literal clone. Empty/unreviewed, override per PR, snapshot and arbitrary unknown materialization could still render a detached empty claim. The regression reproduced the empty-strategy bypass before correction. Compile now considers both reviewed PVC IDs and scan snapshots; only explicit reviewed non-copy policies (mock, ignore, reference, use base, external dependency) bypass this copy refusal. Exclusions and non-PVC cloning retained. Edited-template paths remain guarded.
- UI cleared strategy_required for clone and could label the graph Valid/Resolved by policy without a data-copy executor. PVC blockers now exist independently of graph validation flags, missing review entries and scan policies. Stored clone intent is preserved rather than replaced with empty storage.
- Resource dropdowns distinguish Copy source data (unavailable) from New empty volume (no copied data), include accessible per-resource labels and explain the prerequisite even when no scan policy is present. Compile remains blocked for unimplemented or implicit copy materialization.

New tickets: control-plane/issues/2026-10-10/production-readiness/pvc-copy-gate-implicit-materialization-bypass.md and frontend/issues/2026-10-10/production-readiness/pvc-clone-review-falsely-resolves-copy.md; each contains a Codex prompt.

## Verification and upstream integration

- API focused regressions and full server race suite PASS; full control-plane golangci-lint zero issues; brand/diff PASS.
- Frontend was rebased onto the independently merged Next.js 16.4.0 update (8c622db), clean lockfile install performed, then 482 unit tests, typecheck and lint PASS. Expanded mock Bootstrap/login regression: 26 passed, including saved copy intent, explicit empty choice and copy refusal with a valid source graph.
- Production frontend build on Next.js 16.4.0 PASS; output preserved privately as frontend-build-next164.log. No change to installed runtime.
- An initial unit assertion failed only on capitalized Server validation copy; adjusted the assertion case-insensitively. Strict typecheck then caught an inferred optional undefined entry in the new test fixture; added an explicit Record type and repeated checks successfully. These were test defects, not live storage failures.
- No runtime overlay/deployment, source data access or live copy was performed. Mock/metadata refusal evidence cannot certify data restoration or MySQL consistency.

## Additional unresolved dependency finding

Fresh npm audit reports five high entries from one underlying braces@3.0.3 dev-toolchain advisory GHSA-vfj7-8cjw-p6xm; production-only audit reports zero. Registry latest remains 3.0.3 and 3.0.4 is absent. No forced major Next downgrade, unsupported fork, audit suppression or node_modules patch performed. Open ticket: frontend/issues/2026-10-10/production-readiness/braces-dev-toolchain-upstream-advisory.md. Local application checks are green, but the complete dependency audit is not clean.

## Explicitly not completed

The actual scoped/idempotent copy/restore executor and MySQL consistency/data restoration remain OPEN in bootstrap-pvc-clone-does-not-copy-data.md. Agent PlanStatefulMaterialization builds typed metadata plans only and performs no data operations. These fixes refuse unsafe materialization and correct UI claims; they are not data-copy implementation. The installed candidate has not received the source changes, so live acceptance is pending deployment. Do not close the parent implementation ticket or claim full production readiness.
