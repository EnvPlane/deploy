# Verified owned singleton-index SQL live iteration

## Approved artifact and first actual gates

User explicitly approved exact owned singleton INDEX as the desired immutable
source/target artifact, not a runtime equivalence waiver. Every plan/driver/
transport allowlist uses the identical full index reference. Native checks were
not modified. Index bytes, sole arm64 descriptor, config and unchanged official
parent filesystem layers are independently hash verified by the harness loader.

Run `3109e0ae0ee1f098` real source/writer/diagnostics Pod imageID matched EXACT:
`docker.io/aaa-envplane-fixture/mysqlcopy-3109e0ae0ee1f098@sha256:ba58c1844a7352e6c08067708553224ae0782d7cffec8d19d6e03fbbc68e0258`.
The unique repository aliases were new; preexisting aliases unchanged. Synthetic
index provenance is retained, not removed or guessed equivalent to its child.

Actual policy `envplane-pvc-copy-fence-3513ec7c4fe183bbfa3da500b83bbad8`:
generation 1 / observedGeneration 1 / `typeChecking={}`. Actual server dry runs
passed SQL positive, filesystem positive, and exact Deny challenges for private
Secret projection, source PVC, fsGroup, SELinux, init command and unrelated name.
This closes the original CEL quantity compilation blocker for THIS rendered
policy/cluster generation. It is not backup/restore proof.

## Ticket SQL-LIVE-004: scoped transport command runner wiring

The first native stale-UID negative returned redacted operation error before
source SQL. The host adapter gave its explicit context/principal command runner
to NativeDriver but omitted `KubeTransport.Commands`; credential GET preflight
therefore fell back to OSKubectl without explicit fixture context. Its requested
namespace/name were only the fresh fixture namespace and `source-app`; no
existing database/source names were submitted, and no SQL/copy ran. The harness
did not treat that redacted failure as UID proof and stopped.

Fix implemented in deploy-owned adapter only: one constructor supplies the SAME
scoped command runner to both NativeDriver and KubeTransport. Regression test
requires explicit command runner, context and fixture principal; driver and
worker code unchanged. Exact source GET UID mismatch is now independently
observed as metadata; refusal proof requires that mismatch, no Restore attempt
and absent target PVC, not a guessed generic error string.

Implementation prompt if regression recurs: keep all native object, Secret and
exec calls on the explicit isolated kubeconfig/context/fixture principal; never
fall back to default OSKubectl. Preserve stdout/SQL/credential redaction and
native failure semantics. Replay fresh fixtures through actual negative and
positive gates, then verify UID-scoped cleanup. Never infer live copy from
mocked transport tests.

Run `3109e0ae0ee1f098` ledger cleanup completed with `cleanupErrors=[]`.
Evidence `/private/tmp/mysqlcopy-live-3109e0ae0ee1f098-build/sql-ledger.json`.
Fresh replay `34496abd3c43c1e4` is separately source-snapshot built; execution
results will be appended only after actual live checks and cleanup.

## Fresh scoped replay 34496abd3c43c1e4: actual progress, not PASS

Fresh exact index Pod identity and current mixed policy generation 1 with
`typeChecking={}` passed. SQL and filesystem positives, all six exact Deny
negatives passed. Stale plan source PVC UID was observed against actual GET
metadata; native refused before Restore/target PVC. Duplicate target root/app
password was refused before target writes. A new target-root client performed
VERIFY_IDENTITY TLS against the source and received MySQL 1045: target root
password cannot authenticate there. Its RAM client config was UID/GID
999:999 mode0600.

Actual native held backup lock challenge returned MySQL 1205 on fixture-root
ALTER while active writer progressed from 4239 to 4249 rows. Actual Restore was
attempted, target helper reached Succeeded/exit0, and native journal recorded a
successful seventh create (consistent with receipt creation in this protocol).
The adapter had not yet captured resource kinds/receipt bodies, so no table
proof/receipt PASS is inferred from that count. Native positive result was
still an operation error and cleared its returned receipt. Retry/cancellation
were not executed because the positive result failed.

### Ticket SQL-LIVE-005: native lifecycle cleanup failure

Observed last phase: positive Restore/target exit0 followed by native deletion
and repeated GETs, ending with a failed GET and overall redacted operation error.
`DomainExecutor` currently gives cleanup 10 seconds; native source helper has
30-second termination grace, and `NativeDriver.Cleanup` waits for exact UID
absence. This budget mismatch is a likely cause, not yet independently proven
by captured context error. No timeout extension, deletion-acknowledgement waiver,
worker/profile code edit or forced Pod removal was made in the harness.

Implementation prompt for native worker owner: reproduce helper deletion under
real KubeTransport and exact own UID; ensure source helper exits promptly or
align bounded cleanup budget with grace/polling. Keep fail-closed success on
cleanup failure and require actual UID absence. Fix in worker-owned code with
regression tests and replay real fresh fixture; do not hide failure in host
adapter or publish until native copy/restart/cancellation gates pass.

Harness instrumentation now records immutable receipt proof ONLY from an actual
successful ConfigMap CREATE response, plus native Cleanup error/context status,
without changing native behavior or retaining Secret/SQL values. Fresh final-
committed-source replay will confirm exact copy-vs-cleanup boundary.

Both own replay namespaces were removed via UID preconditions;
`sql-ledger.json` reports `cleanupErrors=[]`. Existing apps/sources untouched.
Evidence `/private/tmp/mysqlcopy-live-34496abd3c43c1e4-build/`.
