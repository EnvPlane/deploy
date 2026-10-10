# Strict native Kubernetes MySQL copy verification: PASS

## Outcome and freeze

Fresh isolated run `2c768207c56785e3` completed all real native Kubernetes gates:
`livePassed=true`, `checksPassed=true`, no error, `cleanupErrors=[]`. This is the
strict replay that closes the secondary cancellation release failure; earlier
`4160` remains corrected false as historical evidence, not retroactively waived.

| Frozen artifact | Exact identity |
| --- | --- |
| Cluster | `kind-envplane-readiness-682` |
| kube-system UID | `49918e1f-d1f7-4aba-9afb-a4cea4187822` |
| Runner | `1e227dbdeb8a598f4d9e18e1eabc4ddb89365c2c` |
| Source renderer | `2d85d8e793d04ee88e167dbf7de5428c6e5e034f` |
| Contracts | `e69da40601a0bdaf3275d1d27ed0063636573a0e` |
| Deploy harness | `ce41cfd7`, after remote merge `13dcc3a6` |
| Source snapshot SHA256 | `db98995ed172b4a8f8b7030fbf96ba8d1fc9e5b7a8c6bca3de003b335930eba9` |
| Root helper | `ghcr.io/envplane/runner@sha256:b881e36b751077a19ac6e8d86a6ee3d5c587782d5f4f5e8a32c548cad442cb80` |
| Helper binary SHA256 | `d35930c36de3cf0ce046b3bdbc8437031a5b194b0ed5dc1ae05b36bd562ede5f` |
| Native adapter SHA256 | `fdf917cacc08a3bba4aa2859faaae034623f1b416afd12ba8eb3ce43c1225cb5` |
| Owned MySQL INDEX | `docker.io/aaa-envplane-fixture/mysqlcopy-2c768207c56785e3@sha256:81d10f9f5a5e01a111d71bdbdf55fe8c399f910a69b2c7aa2363d6c489ee1a08` |
| Sole arm64 manifest | `sha256:b462e4f0e5c0e5a2fb1dcf9d1f5320230576fc46187411752694a8759378cbfb` |

The helper binary was verified inside its OCI archive. MySQL singleton index,
sole platform/config and all unchanged official parent filesystem layers were
hash verified. Actual source/client imageID equaled the identical approved full
index ref used by source, target and trusted allowlists. No index/child/config
equivalence waiver. Loader verified all preexisting aliases unchanged.

No code/docs commits during build/replay. After completion, read-only source
comparison reported `sourceSnapshotUnchanged=true`, `changedPaths=[]`. This
report is the only subsequent change; no executable changes or push by this task.

## Actual live gates

| Gate | Observed evidence |
| --- | --- |
| Fresh TLS MySQL / InnoDB writer | Real StatefulSet/client startup; VERIFY_IDENTITY queries; active auto-increment INSERT writer |
| Mixed CEL | `envplane-pvc-copy-fence-af2fa381518c6501a45add22389024c8`, generation1/observed1, typeChecking={} |
| Effective admission | SQL+FS server dry-run positives; exact Deny Secret/PVC/fsGroup/SELinux/init-command/unrelated-name negatives |
| Secret/principal isolation | Exact app/backup/public CA access; private source root/writer/TLS/bootstrap GET forbidden; real target-root-to-source authentication1045 |
| Target root independence | Native duplicate root/app credential refusal before writes; independent generated target root; RAM config999:999:0600 |
| Source UID drift | Actual source GET mismatch against stale plan, refusal before Restore/target PVC |
| Backup/DDL/DML | Actual held native backup lock; fixture-root ALTER1205; writer4242->4252 positive,4761->4771 retry,5095->5105 cancel |
| Positive copy | Native success=true, matching logical proof, shutdown verified, real immutable receipt, cleanup error/context empty |
| Completed retry | Same PVC+Secret reopened; identical returned receipt; re-dump logical proof; no Restore; shutdown and cleanup passed |
| Cancellation | Actual1024 Restore bytes; only transfer/cancelled; exact FailureStages=[transfer]; no release/cleanup secondary |
| Partial-target retry | Only inspect_target/partial_target; exact FailureStages=[inspect_target]; no Restore; clean helper cleanup |
| Source preservation | Rows4113->5588, same server UUID/PVC UID/schema hash, marker count1 |
| Final cleanup | Own namespaces/fences/readers absent; all3 exact own Delete-policy PVs reclaimed |

### Strict secondary failure proof

Actual cancellation result, not a mock or parsed generic refusal:

```json
{
  "success": false,
  "restoreAttempted": true,
  "cancelInputBytes": 1024,
  "errorStage": "transfer",
  "errorCode": "cancelled",
  "failureStages": ["transfer"],
  "cleanupError": "",
  "cleanupContextError": ""
}
```

Actual partial retry:

```json
{
  "success": false,
  "restoreAttempted": false,
  "errorStage": "inspect_target",
  "errorCode": "partial_target",
  "failureStages": ["inspect_target"],
  "cleanupError": "",
  "cleanupContextError": ""
}
```

The harness rejects missing/extra stages and any cleanup error. No timeout,
release acknowledgment, clean-exit, UID-absence or fail-closed waiver was applied.

## Positive receipt and source preservation

Immutable receipt UID `f7a98e1e-4ac7-4782-a295-59675d191c45`, Version1:

- PlanDigest `0625e3331db0d9178349640773b0ac58c9070f3361397740a4954f67900d49c8`.
- `records` rows4353; raw dump bytes1307341; `ShutdownVerified=true`.
- RawSHA256 `f6167e73bc436389926cbb736eb11e8ccd28cabe170417fd35d9d3baf0f1f4ac`.
- SchemaSHA256 `ba5ceb087d8c9be3afd7cb95dde8bf0c104644fde9d48bc16502fcc02e22fb68`.
- RowsSHA256 `e946b1f745670fe76dc135ccf49ff9322f79865793a63fb0934f7a8b9ff45e76`.
- Source PVC `26f3940d-ceb7-435e-80de-f8d1e6d71d6f`; StatefulSet
  `232556d8-e186-4200-be2e-e34c09ed94df`; server UUID
  `7d7136b4-c4dd-11f1-b7b8-5e3f3e3b3533`.
- Target PVC `53e22f20-cb9a-4131-b1cf-777b2e89beda`; original helper
  `b4c3b37c-189c-496e-a366-7f3816574c22`; generated Secret
  `bdba479a-f793-4d40-b0e0-89210b92dbd2`.

Completed retry returned this exact receipt unchanged. Source rows4113->5588;
server UUID unchanged, schema-column metadata SHA256
`2255af51a08f158eed579f2e871a9b0fcffd0264eada43c5b56d5489688e13b3`
unchanged, marker count1 and original source PVC UID preserved.

## UID cleanup and postchecks

Own namespace UIDs: source `ee7d3948-5df3-43d4-a962-d6fa81dbe806`, destination
`7526d840-6162-4838-abd6-b02c0900753c`. Exact policy UID
`70151907-04de-47cb-912b-54e5b4052900`; binding UID
`d583101e-2b91-4418-a43e-aaa6e394f558`.

Cleanup retained native30s helper grace, independent bounded cleanup, exact UID
preconditions and real helper absence. Fixture-owner cleanup separately deleted
own namespaces and individually UID-bound cluster grants/fences. Ledger
`cleanupErrors=[]`;3 PV reclaims:

- Source `pvc-26f3940d-ceb7-435e-80de-f8d1e6d71d6f`, PV UID
  `f5fe500e-33dd-4e17-8d21-35dc9d9dbd94`.
- Cancel target `pvc-de465abc-899e-4034-8a9a-953df3a6bc13`, PV UID
  `79c2a76b-bfba-4874-8977-bca22c3ea275`.
- Positive/retry target `pvc-53e22f20-cb9a-4131-b1cf-777b2e89beda`, PV UID
  `aecb3bdc-bde9-414f-8a6b-ac22353c36db`.

Final explicit read-only `get --ignore-not-found` postchecks returned no names
for both fixture namespaces, exact policy/binding, all3 PVs and all3 reader
ClusterRole/Binding pairs (`ep-copy-ccdae59fb5a0fe89-fence-c5d6e37db896524f78f4683e`,
`ep-copy-ccdae59fb5a0fe89-sql-ns-68c3bc6a35f29f734d249a58`,
`mysqlcopy-live-2c768207c56785e3-target-ns`).
Fixture source/target data and private credentials were removed with their own
resources; verified local image artifacts remain for evidence. Existing apps,
sources, namespaces, image aliases and drivers were untouched. No broad grants.

## Evidence and acceptance boundary

Private scrubbed evidence:
`/private/tmp/mysqlcopy-live-2c768207c56785e3-build/{sql-ledger.json,sql-native-commands.jsonl,build.json,source-snapshot.json}`
and `/private/tmp/mysqlcopy-live-2c768207c56785e3-mysql/mysql-load.json`.
No source dumps, passwords, client configs or private TLS keys were retained on host.

Local harness checks:17 combined Python checks;5 Go adapter race tests. These
are separate from the actual Kube gates above. Debug/testing-strategy skills
kept the secondary release failure explicit and required this fresh strict replay.

**Boundary:** real NativeDriver+KubeTransport fixture acceptance only. Every
result states `CPLeaseProven=false`. This does NOT prove production CP lease,
authenticated Runner heartbeat/fresh Agent scan enrollment, wizard/readiness UI,
template publication, Flux/Helm end-to-end operation, production storage or HA.
No runtimeReady/UI/production-readiness claim. No push from this task.
