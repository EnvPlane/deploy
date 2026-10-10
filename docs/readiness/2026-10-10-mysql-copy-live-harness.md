# Native MySQL isolated live verification

## Scope and acceptance

Human authorization is limited to fresh `mysqlcopy-live-<runID>-src/-dst` in
`kind-envplane-readiness-682`, kube-system UID
`49918e1f-d1f7-4aba-9afb-a4cea4187822`. No baseline database, existing application,
existing source Pod exec, broad source grants, driver/profile edits or push.

The harness uses real `mysqlcopy.NativeDriver`, `KubeTransport`, current locally
built Runner Root config helper, and the actual source-onboarding renderer.
SQL and filesystem source exceptions share one reviewed Deny policy, with a
distinct empty filesystem-probe PVC. Positive SQL admission and secret/PVC,
fsGroup, SELinux, command and unrelated-name negatives are actual server dry runs.
Typechecking and observed generation must pass before execution.

Fixture-only privileges: app SELECT/SHOW VIEW on fixturedb; backup admin
BACKUP_ADMIN/SHOW_ROUTINE globally and SELECT/SHOW VIEW/TRIGGER/EVENT only on
fixturedb; writer INSERT only on fixturedb. Source root/bootstrap credentials and
TLS private key are not readable by the copy principal. Public CA is separate.
Native source helper has no source PVC and only exact projected credential keys.
Target passwords are independently random, including a distinct root key.

Host journal stores command verbs and status, never arbitrary SQL argv, stdout,
Secret values, dumps or client config. Bootstrap credentials/certificate material
exist in RAM/stdin and fixture Secrets only. Metadata plans contain references,
not credentials. Native source/target cleanup is supplemented by UID-precondition
deletion of own cluster grants/policies and own namespaces.

## Test matrix

| Proof | Mechanism | Acceptance |
| --- | --- | --- |
| Local adapter | Go race tests, Python harness tests | Not live evidence |
| TLS / identity / source schema | Real native readback and VERIFY_IDENTITY | Exact source identities |
| Admission | Mixed canonical policy, server dry runs | Current generation, no CEL warnings, exact Deny |
| DDL fence | Fixture root ALTER while native backup hold acquired | MySQL 1205, not privilege denial |
| Active DML | Count before/after blocked ALTER | Writer progresses under backup lock |
| Backup/restore | Native bounded dump/restore and logical receipt | Matching table rows/schema hashes, clean shutdown |
| Restart | Fresh native driver on completed target | Identical receipt and logical proof |
| Cancellation / partial retry | Cancel actual Restore reader at 1024 bytes | No completion; retry never Restore |
| Target root isolation | Pending independent live probe | Do not infer from random generation |
| Source UID drift | Pending independent live probe | Must refuse before target writes |
| Cleanup | Exact own UID DeleteOptions | Both new namespaces and own cluster objects absent |

Initial iteration is not a full live PASS until the pending independent probes
are implemented and executed. No runtime readiness or control-plane lease proof.

## Commands

```sh
python3 scripts/mysql-copy-live-build.py --run-id <fresh-16hex> --output-dir /private/tmp/mysqlcopy-live-<runID>-build
python3 scripts/mysql-copy-live-image.py --run-id <runID> build --output-dir /private/tmp/mysqlcopy-live-<runID>-mysql
python3 scripts/mysql-copy-live-image.py --run-id <runID> load --image-record /private/tmp/mysqlcopy-live-<runID>-mysql/mysql-image.json --kubeconfig /private/tmp/envplane-readiness-682.t5bJs0/kubeconfig --authorize-fixture <runID>
python3 scripts/pvc-copy-live-load.py --build-record /private/tmp/mysqlcopy-live-<runID>-build/build.json --kubeconfig /private/tmp/envplane-readiness-682.t5bJs0/kubeconfig --cluster-uid 49918e1f-d1f7-4aba-9afb-a4cea4187822 --authorize-fixture <runID>
python3 scripts/mysql-copy-live.py --run-id <runID> --build-record /private/tmp/mysqlcopy-live-<runID>-build/build.json --mysql-image-record /private/tmp/mysqlcopy-live-<runID>-mysql/mysql-load.json --kubeconfig /private/tmp/envplane-readiness-682.t5bJs0/kubeconfig --authorize-fixture <runID>
```

Execution always attempts bounded cleanup in `finally`. Never adopt an existing
namespace/resource or reuse a ledger. Safe blockers are captured in the private
metadata ledger; no database log output is retained.

Unique MySQL image provenance is mandatory for new runs. Only fixture labels
change from the official exact arm64 parent; all filesystem layer descriptors
and contents are hash verified unchanged. No preexisting alias is retagged or
removed. Exact running source imageID must equal the new reviewed immutable
manifest; cached index/config equivalence is never accepted. Build snapshot
hashes bind current Runner/native source and renderer files; concurrent source
changes abort the build. Adapter-only refresh refuses changed helper sources.
