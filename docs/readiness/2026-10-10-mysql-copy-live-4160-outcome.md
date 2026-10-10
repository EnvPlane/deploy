# 4160 native SQL live outcome: copy/retry PASS, release acceptance pending

## Precise closure

Run `4160cdc9c008ad45` proves real Kubernetes native logical MySQL copy,
completed-target reopen/retry, partial-target refusal, source preservation and
full fixture/PV cleanup. **Full lifecycle acceptance is NOT yet PASS:** the real
cancellation result joins an unexpected `release_ddl / operation_failed` with
the expected `transfer / cancelled`. User explicitly required no release waiver.

The old in-flight harness emitted `livePassed=true` because it checked only the
primary cancellation result. That was an acceptance-gate defect. Private ledger
now transparently records `originalHarnessReportedPass=true` and the acceptance
correction, sets `livePassed=false`, and preserves every raw native result,
receipt/hash/UID and cleanup proof unchanged. Updated harness captures bounded
`FailureStages` and rejects secondary release or cleanup failures.

## Immutable freeze

| Artifact | Exact identity |
| --- | --- |
| Cluster | `kind-envplane-readiness-682` |
| kube-system UID | `49918e1f-d1f7-4aba-9afb-a4cea4187822` |
| Runner commit | `7e701559f3381adc58c929fbf889fdc0dccbe871` |
| Source renderer commit | `a74392b82ccec472c2276ff9f50e243a62bfac94` |
| Contracts commit | `e69da40601a0bdaf3275d1d27ed0063636573a0e` |
| Source snapshot SHA256 | `f907af5f1f4ece1f8bd27d67a9583158ac0ace23a18e7e32d9e854c56f89e1c4` |
| Root helper | `ghcr.io/envplane/runner@sha256:a9653ce5dc7fe07ed893f4f7b7db90a2f6ac84d137a202185a8d898a0af455c3` |
| Helper binary SHA256 | `ad49503bdcf829832c55bd562da43b1aa63059f5388d81a07d975e7ac2243e21` |
| Native host adapter SHA256 | `be90839159fddabff40b96e57f32f0a108ed8952bcde7e217c376390c2255b59` |
| Approved owned MySQL INDEX | `docker.io/aaa-envplane-fixture/mysqlcopy-4160cdc9c008ad45@sha256:5e6873c20fb157e2aff09ad52e44cce7e378f80889cddb10a07915fc935053dd` |
| Sole arm64 platform descriptor | `sha256:f30f857d769591b809685864fc1bc88648212197d8cd34c8eb6330d6fc2906a5` |
| MySQL config | `sha256:53aeabb6ff44f2453eeb28cf5603e6c5e07ad1ecd8d9181a36e3dc767c7d0b18` |

Index bytes, sole platform descriptor, config and all unchanged official parent
filesystem layers were verified; actual spec/imageID exact full-ref equality
passed. No runtime index/child/config equivalence was accepted. All preexisting
node image aliases remained unchanged.

## Actual gates

| Gate | Actual result |
| --- | --- |
| TLS-only fresh source / writer / client | Ready, VERIFY_IDENTITY real queries |
| Mixed source CEL | Policy `envplane-pvc-copy-fence-a36b23b1c5c5f5304ee797c731ae03d0`, generation1 / observed1 / typeChecking={} |
| Mixed admission | SQL+FS positives; exact Deny private Secret/PVC/fsGroup/SELinux/command/unrelated-name challenges passed |
| Source private credentials | Copy principal denied source root/writer/TLS-private/bootstrap Secret GET |
| Stale source UID | Actual GET mismatch, no Restore, no target PVC |
| Target root isolation | Duplicate app/root native refusal before target; actual target-root-to-source TLS auth1045; config999:999:0600 |
| Held source backup / active DML | ALTER error1205; writer4243->4253 (positive),4765->4776 (retry),5099->5109 (cancel) |
| Positive native copy | success=true, receipt returned, shutdown verified, cleanup errors empty |
| Completed retry | same PVC+Secret, reopened server, re-dump logical proof, identical returned receipt, no Restore, shutdown and cleanup passed |
| Actual cancellation | 1024 Restore bytes, primary transfer/cancelled, no success receipt; secondary release_ddl failure NOT accepted |
| Partial retry | inspect_target/partial_target, no Restore, cleanup passed |
| Source preservation | rows4115->5597; same server UUID; schema hash and marker1 preserved; PVC UID unchanged |
| Fixture closure | cleanupErrors=[]; own namespaces/policy/readers absent; all3 exact claim-bound Delete-policy PVs reclaimed |

### Positive receipt

Actual immutable receipt UID `8bd3ccab-bfff-4378-82f2-142776310af1`:

- PlanDigest `83da4ac3aaeb14af2a7da19c52af5b48bf435c8556c36e81a09a519c7f811d9d`.
- `records` rows4353, raw bytes1307341.
- RawSHA `30299021330ffc676bdad2b2d95c292eaf113501c23e8cc67721859622928736`.
- SchemaSHA `ba5ceb087d8c9be3afd7cb95dde8bf0c104644fde9d48bc16502fcc02e22fb68`.
- RowsSHA `73b2261e9a4e82bb52968da05c4b0b13c6fe52e040186856dc04900e8eac04f5`.
- Source PVC `c111a41b-85e6-4fc1-b274-5be74bbcf46b`, StatefulSet
  `0b159765-0815-443c-a1b4-198410f6c2eb`, server UUID
  `72477d09-c4db-11f1-9d95-4e3e99549e29`.
- Target PVC `1df8f156-81db-4322-b336-a2b78e54820a`, original helper Pod
  `ffd0f3c6-cf3c-4157-8d30-7a82cd1b83c0`, generated Secret
  `4b41851d-a6d7-4f91-89e8-cd2028f00548`.
- `ShutdownVerified=true`, actual positive and retry Cleanup error/context both empty.

## Ticket SQL-LIVE-006: cancellation lock-session lifetime / acceptance gate

Actual safe constant error, not guessed from a redacted primary:

```text
mysql copy failed [stage=transfer code=cancelled]
mysql copy failed [stage=release_ddl code=operation_failed]
```

Worker owner isolated the lock session's lifetime coupling to operation context:
operation cancellation ends the session before independent Release can complete.
Repair is worker-owned and underway; no native/profile edits by this harness.

Implementation prompt: detach the backup-lock session from operation cancellation
under an explicit finite lifetime, independently release on the exact connection
with server UUID/connection acknowledgment and clean exit. Preserve failed
ack/exit as real failure, never suppress secondary release errors. Run real
cancelled-operation release evidence plus regression/race/vet/lint; freeze a new
commit/helper checksum, then fresh real positive/retry/cancel/partial/cleanup.
The harness must require bounded FailureStages and reject release_ddl/cleanup
secondary failures, not merely primary cancellation. No forced source mutation
or existing application access.

## Evidence and boundaries

Private scrubbed evidence:
`/private/tmp/mysqlcopy-live-4160cdc9c008ad45-build/{sql-ledger.json,sql-native-commands.jsonl,build.json,source-snapshot.json}`
and `/private/tmp/mysqlcopy-live-4160cdc9c008ad45-mysql/mysql-load.json`.
Only metadata/proofs retained; no credentials, SQL dumps or private TLS files on host.

All fixture namespaces, grants, fences and PVCs were removed;3 own PV reclaims
recorded. Source fixture data/credentials therefore no longer exist. Verified
local image artifacts remain for evidence. No existing apps/sources changed,
no driver change or broad grants, no push by this task.

Local harness checks: five Go race tests; sixteen combined FS/SQL Python checks.
The debug and testing-strategy skills separated actual data proof, cleanup,
secondary release failure and local checks rather than collapsing them into PASS.

Every native result says `CPLeaseProven=false`: this exercises NativeDriver /
KubeTransport with fixture authority, NOT the production CP lease, Runner
heartbeat/Agent scan enrollment, policy compile/readiness UI, template publish
or deployed Flux/Helm workflow. No runtimeReady/UI/production-readiness claim.
