# MySQL native live rerun: partial, unresolved CRI identity blocker

## Outcome

**NOT SQL live PASS.** Latest run `a916c097e0d1b17a` reached a fresh MySQL 8.4.11
source Pod Ready, then stopped at strict actual-image identity verification.
No native backup/restore, DDL hold challenge, cancellation, restart or root/UID
negative acceptance ran. The corrected SQL CEL renderer was built, but this
run stopped BEFORE its policy was installed; current-generation zero-warning
CEL compilation and mixed SQL/FS probes remain unproven live.

Earlier run `863b4f86af0ae93b` established fresh source/writer/diagnostics Ready
and a native MySQL client query over VERIFY_IDENTITY TLS. It stopped at actual
CEL quantity-field typechecking errors. That is partial fixture evidence, not
copy acceptance, and must not be combined into a fictitious completed suite.

## Current immutable build and provenance

| Item | Exact evidence |
| --- | --- |
| Cluster | `kind-envplane-readiness-682` |
| kube-system UID | `49918e1f-d1f7-4aba-9afb-a4cea4187822` |
| Official arm64 parent | `docker.io/library/mysql@sha256:ca3f0494c0f1fc86eb45f5e4786a1bb9f64d2f85b562cc74a9595046f6519a42` |
| Unique fixture MySQL manifest | `ghcr.io/envplane/mysqlcopy-fixture@sha256:952f0d9e2fb677060856e6af54dc1b65df789dc678ef88fd90c1b5cde032e6d2` |
| Fixture MySQL config | `sha256:0a7dab76e3e7148ff607dcc52d26c75d01a83f0bf8dd02b3058ca0f38fb6c36c` |
| Current Root helper | `ghcr.io/envplane/runner@sha256:493ec58758e912c5c6928a510aa9b50f1715aace870a00a6aa5874a0ab786d57` |
| Helper binary SHA256 | `e4e1fe2adf0c900f5f7f92c2db69492b312a06b7a62af98ce902b851b4e61553` |
| Native host adapter SHA256 | `eb7eb5a8e0466da8d458e2c72682aca614f748d0debecfa7438d32da8361ec3f` |
| Runner commit | `c59b73ab4fdb743a81bf8a6c134a0136abb7de00` plus recorded local worktree |
| Renderer commit | `8751340bda7c4b0a1c9c3688012b662a53445765` |
| Source snapshot SHA256 | `8917e37ac38a2d1c55cfd0d2c945950ee4fd89f4b9d445aa4d16172531072224` |

The unique MySQL image changes only fixture provenance labels. All ten parent
filesystem layer digests and archive blob bytes were verified unchanged. Every
preexisting kind-node image alias was verified unchanged by the loader. No
publication, push, driver waiver, existing source/app access or mutation.

## Ticket SQL-LIVE-003: CRI retains removed synthetic import repoDigest

The loader proved and removed ONLY its newly introduced archive index alias:
`import-2026-10-10@sha256:1cd3011792b190bc253ddecbc7a9cd0742f69fa70f4842f39cc7dda125599c9f`.
It was absent before import and the exact singleton OCI index points to the
owned fixture platform manifest. No preexisting aliases or image content were
deleted. The fresh source Pod UID
`0a8db7c4-f54c-4d5e-80d4-ea489571fa8c` nevertheless reported:

```text
docker.io/library/import-2026-10-10@sha256:1cd3011792b190bc253ddecbc7a9cd0742f69fa70f4842f39cc7dda125599c9f
```

After full fixture cleanup, read-only `ctr images ls` showed the exact unique
fixture platform tag, digest reference and config-ID alias, but NO own synthetic
index alias. Read-only `crictl inspecti` still showed both repoDigests:

```text
docker.io/library/import-2026-10-10@sha256:1cd3011792b190bc253ddecbc7a9cd0742f69fa70f4842f39cc7dda125599c9f
ghcr.io/envplane/mysqlcopy-fixture@sha256:952f0d9e2fb677060856e6af54dc1b65df789dc678ef88fd90c1b5cde032e6d2
```

This is actual containerd/CRI metadata divergence, not manifest/config digest
equivalence permission. Strict worker image validation and harness gate remain
unchanged. No source Pod was repinned, no existing image aliases retagged, no
node/CRI restart or broad image-cache purge attempted.

Implementation prompt for harness owner: avoid creating the synthetic index
repoDigest during initial fixture-only import, or refresh ONLY provably owned
unused fixture image metadata with exact preflight/ref/readback safeguards.
Prove new Pod `status.imageID` equals the reviewed immutable manifest BEFORE
source onboarding. Do not change preexisting aliases, existing containers,
driver image checks or accept index/config equivalence. Use a fresh run and
current source-snapshot-verified Runner/renderer; then replay actual mixed
policy zero-warning CEL, SQL+FS positives and exact Deny negatives before native
TLS backup/restore/restart/cancellation/source-preservation proof.

## Resource closure

Latest run created 16 explicitly recorded fixture resources. Namespace UIDs:

- `mysqlcopy-live-a916c097e0d1b17a-src`: `758b3346-aa56-4753-8b7d-3cdead32215f`.
- `mysqlcopy-live-a916c097e0d1b17a-dst`: `5fa61e07-6800-4604-b8c5-81da8ba15122`.
- Source PVC UID: `bddcd04a-8eef-4de1-b664-8e452920e8d9`.
- Empty filesystem-probe PVC UID: `98fb118e-fe26-491d-a3d7-3e6d3195a8fb`.

UID-precondition namespace cleanup completed; ledger `cleanupErrors=[]`.
Read-only postchecks confirmed both latest namespaces, both prior
`77c835c7a0299753` namespaces, and the PV for the exact latest source claim UID
absent. No profile Roles, policy or binding were created in either of these
two image-blocked runs. Fixture credentials/private TLS material disappeared
with their own namespaces. Verified fixture image artifacts/cache remain for
evidence; no broad cache cleanup was performed.

Private scrubbed evidence:

- `/private/tmp/mysqlcopy-live-a916c097e0d1b17a-build/sql-ledger.json`
- `/private/tmp/mysqlcopy-live-a916c097e0d1b17a-build/build.json`
- `/private/tmp/mysqlcopy-live-a916c097e0d1b17a-build/source-snapshot.json`
- `/private/tmp/mysqlcopy-live-a916c097e0d1b17a-mysql/mysql-load.json`
- `/private/tmp/mysqlcopy-live-77c835c7a0299753-build/sql-ledger.json`

Own implementation commits: `3623b5d4` unique OCI provenance/fresh snapshots;
`264f7e56` exact own synthetic-index retirement. No push. Local checks: four
Go adapter tests under race and four Python harness/provenance checks passed.
The testing-strategy skill keeps these local checks distinct from live gates.

## Closure boundary

Fixture resource cleanup is closed. SQL live acceptance is still partial and
blocked. Remaining gates include actual corrected CEL/admission, native TLS
backup with active writer and held DDL challenge, restored logical row/schema
proof, shutdown/restart receipt retry, target-root isolation, cancellation/
partial-target refusal, source-UID drift and source schema/identity preservation.
