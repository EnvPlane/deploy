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
