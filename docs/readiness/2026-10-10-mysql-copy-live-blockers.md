# SQL live iteration 1: real blockers, not acceptance

Run `863b4f86af0ae93b` on approved isolated kind cluster, kube-system UID
`49918e1f-d1f7-4aba-9afb-a4cea4187822`. Local adapter checkpoint `ff53a297`.
Private scrubbed metadata evidence:
`/private/tmp/mysqlcopy-live-863b4f86af0ae93b-build/sql-ledger.json` and
`sql-profile-review.json`. Source data, passwords, TLS private keys and client
configs were not persisted on the host or printed.

Build provenance:

- Runner commit `324076bb087c4398b5832d5c34c90d6ec2d112c4` (dirty worktree recorded).
- Control-plane renderer commit `0c5a92458c8b30d8039625922eeffae58941a3d3`.
- Root helper binary SHA256 `df69c7666d6b0d919a381ae4da73c77a4b03b3f09eb2ad8ed8ecf51166ffb492`.
- Verified OCI helper `ghcr.io/envplane/runner@sha256:2707a357e871ed0dab0c26e1ae47e91035af661f0f069b34c1fdbbf2aa270fcb`.
- Host SQL adapter SHA256 `8b5dc398c4f75294ed342eaf6873eb1f41062248b8efde3f7177feff4338162b`.

## Ticket SQL-LIVE-001: actual mixed source policy CEL typechecking

Observed generation 1 of policy
`envplane-pvc-copy-fence-3cecf64ccfbaba7a0ef1fc43d15ef1ed`, UID
`be665181-9dd8-4e89-8744-ac2685b3b426`, failed on
`spec.validations[1].expression`. The approved Deny binding UID was
`633a1122-170f-42b3-9cfb-f843f6ae0548`.

Actual safe server errors (column numbers retained):

```text
/v1, Kind=Pod: ERROR: <input>:1:8044: undefined field 'limits'
ERROR: <input>:1:8131: undefined field 'limits'
ERROR: <input>:1:8182: undefined field 'limits'
ERROR: <input>:1:8243: undefined field 'limits'
ERROR: <input>:1:8297: undefined field 'limits'
ERROR: <input>:1:8327: undefined field 'requests'
ERROR: <input>:1:8416: undefined field 'requests'
ERROR: <input>:1:8469: undefined field 'requests'
ERROR: <input>:1:8535: undefined field 'requests'
ERROR: <input>:1:8591: undefined field 'requests'
ERROR: <input>:1:12148: undefined field 'limits'
ERROR: <input>:1:12243: undefined field 'limits'
ERROR: <input>:1:12298: undefined field 'limits'
ERROR: <input>:1:12366: undefined field 'limits'
ERROR: <input>:1:12424: undefined field 'limits'
ERROR: <input>:1:12455: undefined field 'requests'
ERROR: <input>:1:12552: undefined field 'requests'
ERROR: <input>:1:12609: undefined field 'requests'
ERROR: <input>:1:12678: undefined field 'requests'
ERROR: <input>:1:12738: undefined field 'requests'
ERROR: <input>:1:16018: undefined field 'sizeLimit'
ERROR: <input>:1:16096: undefined field 'sizeLimit'
ERROR: <input>:1:16343: undefined field 'sizeLimit'
ERROR: <input>:1:16421: undefined field 'sizeLimit'
ERROR: <input>:1:16665: undefined field 'sizeLimit'
ERROR: <input>:1:16743: undefined field 'sizeLimit'
```

Implementation prompt for profile owner: repair SQL CEL generation for actual
Kubernetes schema/typechecking, without reducing no-PVC, exact Secret projection,
root init capabilities, fsGroup/SELinux, command or name restrictions. Rebuild
actual metadata renderer; run fresh mixed-policy positive and exact Deny
challenges on the isolated cluster. Do not treat string generation tests as
live CEL compilation. Harness must continue refusing any expressionWarnings.

## Ticket SQL-LIVE-002: cached CRI index identity versus platform pin

Spec requested trusted arm64 MySQL 8.4.11 platform manifest:
`docker.io/library/mysql@sha256:ca3f0494c0f1fc86eb45f5e4786a1bb9f64d2f85b562cc74a9595046f6519a42`.
All three new fixture Pods instead reported imageID:
`docker.io/library/mysql@sha256:6ea90827b1100f8f2ae306a539f86d2c264a26ed435a2a9f75551dd5c3aeb242`.
That is the preexisting cached multi-platform index, whose previously read
arm64 descriptor is the pinned manifest. The native driver's strict image
comparison remains unchanged; the copy did not reach that check because CEL
typechecking stopped earlier. No acceptance of index/config equivalence was
inferred or patched into the driver.

Implementation prompt for harness owner: prepare a unique fixture-only MySQL
OCI image/reference derived locally from the verified exact MySQL platform
digest, retain parent/manifest/config provenance and confirm actual new
container `status.imageID` equals the new immutable manifest. Do not remove or
retag any existing image aliases, alter existing Pods or weaken native image
checks. Rebuild/load a fresh exact helper if helper package code changed.

## Actual execution and cleanup

28 explicitly created resources were UID recorded. Source namespace UID
`9af1fd4f-5178-49a6-8d96-7afb5af895a3`; destination UID
`4957f8d9-1ed6-4208-a6fb-6c2366505e7c`. Source StatefulSet UID
`7e8cf3c2-5e53-4b14-bb8b-80c30c011d76`, source Pod UID
`9917c157-53ee-4abb-9f85-aa86faf87ba1`, source PVC UID
`bacb1f5c-d8d1-42a0-b476-11e43488eed4`, source Service UID
`3d34c046-7db4-44ae-8a8e-d44d28b917a6`.

Fresh source server, writer and diagnostics client reached Ready. A fixture
root SQL count/server UUID query succeeded over VERIFY_IDENTITY TLS before
profile installation. SQL dump/restore, held DDL challenge, completed retry,
cancellation, root-isolation and UID-drift acceptance were NOT executed in this
run. No production readiness or CP lease claim.

Cleanup used UID-precondition DeleteOptions for own cluster resources and own
namespaces. Ledger `cleanupErrors=[]`. Read-only postchecks confirmed both
namespaces and exact policy/binding absent, and no PV with the exact source
claim UID. No existing app/source data was accessed or changed. No push.

Local checks: four Go adapter tests pass under race, Go vet passes, three Python
harness checks pass. They are local checks, not live acceptance evidence.
