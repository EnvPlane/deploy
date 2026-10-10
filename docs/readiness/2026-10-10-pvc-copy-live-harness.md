# Disposable PVC-copy live verification harness

Status: authorized live filesystem suite PASS on fresh run `85f6c7da53d2ec8a`;
cleanup CONFIRMED. The initial CEL blocker below was fixed by the Runner owner
and the corrected policy passed real positive/negative admission. No
existing source data, application workload, authentication, chart, profile or
storage driver changed. Only new owned fixture namespaces/RBAC/fence were created
and removed. MySQL, CP/Agent lease integration and runtime readiness NOT ASSERTED.

## Verification gap / implementation ticket

The native Runner copy protocol has local tests but lacks isolated live
filesystem/mount/admission evidence. Implement a fixture-only executable driver
and orchestration harness, gated on explicit execution authorization and reviewed
source onboarding. Verify bytes, marker, numeric ownership/modes including root,
idle/read-only source preservation, completed retry, cancelled/partial refusal,
stale source UID refusal and exact-identity cleanup. Never substitute a mock
result for a live result. No chart/profile changes, broad grants or pushes.

Codex prompt: use the real Runner DomainExecutor and source fence checks; create
only collision-refusing uniquely named fixture namespaces after authorization;
capture a preservation ledger and compare before/after. Fail closed on unknown
identity, incomplete listings, failed admission, missing review or partial target.
Keep all existing sources and test-app/MySQL outside scope. External reviewed
onboarding and live execution remain separate owner-controlled acceptance gates.

## Read-only discovery (2026-10-10)

Requested kubeconfig: `/private/tmp/envplane-readiness-682.t5bJs0/kubeconfig`.
Context: `kind-envplane-readiness-682`. Cluster identity (`kube-system` UID):
`49918e1f-d1f7-4aba-9afb-a4cea4187822`.

- One Ready arm64 control-plane node, Kubernetes `v1.37.0`.
- `standard`: `rancher.io/local-path`, Delete, WaitForFirstConsumer.
- No CSI drivers; admissionregistration v1 policy/binding API resources exist,
  but the ValidatingAdmissionPolicy inventory is empty.
- `envplane-executors` Agent and Runner deployments each have one Ready replica.
- Installed Runner image digest: `4a624292408a62247b6044a66ed72b2670a96d917a7615040eaaaa9b88632ae9`.
- Installed API image digest: `27ae6fc479b2e49fe6017eee7a5b03f436d525ba016bbf32932751c73b60b321`.

These observations do not establish installed PVC-helper compatibility or
reviewed copy capability. No exec, source PVC/data inspection or writes occurred.
The first connection was sandbox-denied, then authorized read-only discovery
succeeded. A zsh glob error affected only the first deployment-image listing;
the quoted, namespace-scoped retry succeeded.

## Authorized live fixture and early blocker

User subsequently explicitly greenlit fixture-only live mutations. Source and
destination names were checked absent before creation; neither was adopted.

- Run: `60a5a5ee57620a88`.
- Source namespace: `pvccopy-live-60a5a5ee57620a88-src`, UID
  `66ef2bcb-20b0-4ec0-a18f-cab410137b55`.
- Destination namespace: `pvccopy-live-60a5a5ee57620a88-dst`, UID
  `999900da-3ab1-4b1b-bf9b-97c66c722e2d`.
- Main source claim: `source`, UID `6578790a-197e-41b1-8290-7c00624cb88c`.
- Separate UID-drift probe: `uid-probe`, UID
  `cc5f9346-3fa5-4c8f-88f3-1e4285bf6034`. Both are Bound native filesystem 64Mi
  claims using the existing standard StorageClass; fixture initializer completed
  and its exact UID-owned Pod deletion was confirmed.
- Expected fixture: marker text includes the run ID, 1MiB zero bytes, root
  UID1000/GID2000/0770, marker0640, payload directory0750, binary0600.
  Expected canonical receipt: 1,048,616 bytes, four entries, tree SHA256
  `8e41b045c4dbdca0e9e5c2d84fe4fdaa888a20e5dd746c29aed9f69f67e90b88`.
  This is independently computed expected data, NOT verified live copy evidence.
- Fixture principal:
  `system:serviceaccount:pvccopy-live-60a5a5ee57620a88-dst:copy-runner`.
  Helpers use namespace default SAs with token automount disabled. Source Role
  grants exact source/probe PVC GET, fixture namespace controller/pod inventory,
  helper CREATE fenced by the source policy, and exact helper-name exec/delete.
  Destination Role has finite PVC/Pod/exec permissions only in its new namespace.
  The sole ClusterRole is GET-only, resourceNames-limited to the exact fence /
  binding and the two namespace identities plus kube-system. No Secrets, wildcards,
  existing namespace grant, source PVC mutation grant or broad admin role.
- Fence policy/binding:
  `envplane-pvc-copy-fence-480a63fae66c78d5cd6eed2b181d8b3e`.
  Policy UID `40aadf4f-e5cc-406e-b316-b9ed5099fb99`, generation1,
  observedGeneration1, typeChecking `{}` (no warnings).
- Actual server-side writable/fsGroup/SELinux challenge creates were denied by
  this exact policy and binding, with its full source-bound digest message.
- The positive read-only helper create then failed BEFORE helper creation and
  BEFORE destination PVC creation. Safe captured error:
  `ValidatingAdmissionPolicy ... denied request: expression ... resulted in error: no such key: subResource`.

### Initial P1 blocker (owner fix and successful live replay recorded below)

The shared Runner fence uses `request.subResource == ''` for CREATE. On this
real API server, absent subResource produces a runtime CEL error even after
successful type checking. Negative denials alone cannot certify positive-path
acceptance. Preserve all fsGroup/SELinux/readonly/identity guards.

Codex implementation prompt for the Runner owner: guard absence of
`request.subResource` with `has(...)`, retaining rejection of nonempty subresources;
regress positive helpers with absent/empty subResource and unsafe injections;
rebuild the host harness driver from the corrected package, refresh ONLY the
recorded UID-owned fixture policy, verify fresh observedGeneration/typeChecking,
then replay negative probes and the positive helper. Do not alter application
namespaces, install broad grants, bypass RequireAdmissionFence, or call this copy
complete. This report is the scoped defect ticket; no out-of-scope repo edits.

## Local build and harness checks

Local host driver and actual Linux/arm64 Runner main built against sibling local
Runner/contracts/gitops, without edits to those repos. This is not publication
compatibility evidence. Helper binary SHA256:
`e349be25fe6b6e36c571e1461d54b1889a063fda987dbf12e78ed6daf04916a8`.
Verified OCI helper reference:
`ghcr.io/envplane/runner@sha256:0ad168f4fa4418c0ba12f7a7954253054e3b27853e3585f4a732eb141395ae5b`.
Archive SHA256: `49da9daacea2e08c99893cc858285ce792f183a54fae35a0b4e3f72735fca206`.
The manifest/layer/binary hashes were verified locally and the image imported
only into this kind node. No push or existing workload image replacement.

kind imported the tag but not its repository@digest CRI alias, causing fixture
initializer ImagePullBackOff. Registering the verified exact alias in the same
node cache resolved it. `pvc-copy-live-load.py` now handles this without force
overwrite or remote publication. This was a fixture-loader issue, not data-copy
success/failure. The harness also uses a separate fixed read-only target-state
diagnostic because native copy Exec intentionally permits only pvc-* RPCs.

Local-only checks: eleven Python mocked safety tests PASS; four Go host-driver
tests with race detector PASS. These are NOT live filesystem acceptance.

Private metadata-only evidence:
`/private/tmp/pvccopy-live-60a5a5ee57620a88-build/` contains build.json, OCI archive,
host driver, Linux helper binary, ledger.json, exact onboarding preview/review,
ledger.commands.jsonl and ledger.commands.driver.jsonl. Journals retain argv,
fixture metadata, policy denials and bounded safe refusal diagnostics, never
archive payloads, existing volume data or credentials.

## Executable workflow and acceptance limits

Run build, verify/archive-finalize if needed, then load, plan, prepare, onboard,
run and cleanup. Every mutation requires exact `--authorize-fixture RUN_ID`.
Build uses current local code and no registry push; no contract publication gate.

```bash
scripts/pvc-copy-live-build.py --run-id RUN_ID --output-dir NEW_PRIVATE_DIR
scripts/pvc-copy-live-load.py --build-record NEW_PRIVATE_DIR/build.json --kubeconfig APPROVED_KUBECONFIG --cluster-uid VERIFIED_UID --authorize-fixture RUN_ID
scripts/pvc-copy-live.py plan --ledger NEW_PRIVATE_DIR/ledger.json --run-id RUN_ID --kubeconfig APPROVED_KUBECONFIG --image VERIFIED_IMAGE --helper-binary-sha256 VERIFIED_BINARY_SHA256
scripts/pvc-copy-live.py prepare --ledger NEW_PRIVATE_DIR/ledger.json --authorize-fixture RUN_ID --driver NEW_PRIVATE_DIR/pvc-copy-live-driver
scripts/pvc-copy-live.py onboard --ledger NEW_PRIVATE_DIR/ledger.json --authorize-fixture RUN_ID --driver NEW_PRIVATE_DIR/pvc-copy-live-driver --build-record NEW_PRIVATE_DIR/build.json
scripts/pvc-copy-live.py run --ledger NEW_PRIVATE_DIR/ledger.json --authorize-fixture RUN_ID --driver NEW_PRIVATE_DIR/pvc-copy-live-driver --reviewed-onboarding NEW_PRIVATE_DIR/ledger.review.json
scripts/pvc-copy-live.py cleanup --ledger NEW_PRIVATE_DIR/ledger.json --authorize-fixture RUN_ID --confirm-exclusive-namespaces RUN_ID
```

`refresh-fence` is restricted to an idle, target-free preflight refusal and only
replaces the exact recorded policy spec with current native Runner output, using
UID/resourceVersion tests. It does not weaken or synthesize the library fence.
`run --retry-preflight-only` likewise refuses any existing target or nonempty
live-result history. Unknown create/deletion outcomes remain operator blockers.

Successful run requires live source tree receipt vs independently computed
fixture, exact source/target UIDs and immutable plan, complete retry, fresh
read-only target remount/rehash, cancellation after a bounded actual stream,
claim/no-completion readback, partial retry refusal, actual recreation of the
separate owned UID probe and stale-plan refusal before allocating its target,
source UID/PV/root/hash preservation, and zero retained helpers/controllers.
Cleanup uses recorded namespace/object UIDs and resourceVersions, never label
sweeps; only exact owned fixture policies/bindings/readers are eligible.

This host adapter tests native DomainExecutor, not authenticated CP leases,
Agent heartbeat/scan integration, UI Compile, complete production readiness or
Environment Ready. No logical MySQL proof is claimed. A later separate MySQL
fixture must keep an active InnoDB writer during protected transactional backup,
use fixture-only root/backup credentials, verify transaction/snapshot consistency
and checksum/restored rows/continued writes, and use the main worker/helper
interface. Existing test-app/MySQL sources remain completely out of scope.

### First-attempt cleanup and fix handoff

Cleanup of run `60a5a5ee57620a88` CONFIRMED: both namespace UIDs, exact own fence
policy/binding and ClusterRole/binding were deleted with UID/resourceVersion
preconditions. Both allocated fixture PVs were confirmed automatically reclaimed,
without manual storage-driver/data-path/PV changes. No destination claim existed.
Private ledger is marked cleaned; evidence and the local helper archive remain.

The Runner owner subsequently reported the optional-subResource guard fix.
Because the recorded old policy UID no longer exists, it must NOT be adopted or
refreshed by name. A new unique run under the same fixture-only greenlight is
required, rebuilding the host driver/helper and recording new identities.

## Successful live replay after the Runner owner's fix

Run `85f6c7da53d2ec8a` used fresh, collision-checked namespaces and recorded all
new UIDs. The deleted first-run policy was never adopted/recreated by old identity.
Reviewed diff changed only the optional request field to
`(!has(request.subResource) || request.subResource == '')`; fsGroup/SELinux,
recursive-readonly, exact-helper/Runner and tokenless/security guards remained.

| Live evidence | Result |
| --- | --- |
| Actual policy generation1/observedGeneration1/typeChecking `{}` | PASS, no CEL warnings |
| Writable, fsGroup and SELinux source-mount server dry-runs | PASS, exact bound policy denial; no second CEL error |
| Positive source helper / live binary SHA256 match / recursive readonly | PASS |
| Independent expected source marker/bytes/UID/GID/modes/root/tree receipt | PASS |
| Actual DomainExecutor source-to-new-target filesystem transfer | PASS, verified UID-bound completion marker |
| Completed same-plan retry | PASS, same exact verified completion marker |
| Fresh readonly target helper after prior helpers disappear | PASS, remount/rehash persistence |
| Real import cancellation after 8,192-byte bounded prefix | PASS, no completion marker |
| Independent cancelled target claim-present/completion-absent readback | PASS |
| Retry of partial target | PASS, target verify refused before any import; no marker; partial state remains |
| Separate owned UID-probe claim deleted/recreated; stale immutable plan | PASS, new UID refused before target creation |
| Main source UID/PV/root metadata/tree hash before vs after | PASS, identical |
| Final source and target consumers/controllers | PASS, zero Pods/controllers |
| Exact own namespace/fence/RBAC cleanup and four owned PV reclaims | CONFIRMED |

### Exact second-run identities and receipt

- Source namespace `pvccopy-live-85f6c7da53d2ec8a-src`, UID
  `66bc41f0-9d93-4fa2-b951-75cf83ee7da5`.
- Destination namespace `pvccopy-live-85f6c7da53d2ec8a-dst`, UID
  `9bfa13f2-1ff4-4fea-bdd1-cfa5318b8ff9`.
- Main source UID `1f04ed45-0bb3-4cb8-bdfe-97742fd450fa`;
  completed target UID `5e4d8a44-52dc-4ea2-a5dd-4f076c0494ce`.
- Root UID1000/GID2000/mode0770 (JSON decimal504), four entries,
  1,048,616 file bytes, including the 40-byte run-specific marker.
- Source-before = completed target = source-after = independently computed tree
  SHA256 `6e90ee3e033684c94464fbba019716e3525f2ff63de22f12131a27c7d3710de9`.
- Immutable domain plan digest
  `sha256:871e09adbd182c28dd280dae0bfb4c6e01b66252a0bd73ee9e75634aa1c9bd08`.
- Native marker plan digest
  `b85f28de2e1cf13144acee1c5d6a6b332c8abaa8f3c8eb5cdb1a41f96da4e441`.
- Probe UID drift:
  `f0c795d2-145a-4369-a7fc-0190a5b4bc31` ->
  `642d9b7b-f43a-415b-9fbd-da357297a737`. Main source was NOT replaced.
- Source-bound fence name
  `envplane-pvc-copy-fence-631d2018a51c3c1369c77f3802cbba2b`, UID
  `db865b2c-48ff-40e3-8458-e074de66f3cb`. Fresh policy generation1 is expected;
  no previously deleted UID could be refreshed to generation2.
- Helper image
  `ghcr.io/envplane/runner@sha256:17289934426e727f3921220911eedddd00c1c878b38130207fc507cb6b63e4b4`.
- Linux helper binary SHA256
  `a9b6912288402dbd2a7aed5417d33c31378d7173d2839c2384b8712a99ff2585`;
  archive SHA256
  `bc87fed3c3e43b5b20ad6e5f7225f542c0d15efbb726bdc7721f03133ba25ddc`.

The helper binary changed after rebuilding current code, so both host driver and
image were rebuilt/loaded. Build records identify private contracts commit
`266baa59a023848c85eb60f59bb0c708dcf82534` and explicitly disclose local dirty
Runner/gitops worktrees. No contract or image publication was needed/performed.

### Harness fixes surfaced by real execution

1. Native delete acknowledgment is not Pod absence. The initial audit helper was
   still Terminating and the real consumer guard correctly refused copying.
   Harness now waits for every exact recorded helper UID to disappear before
   advancing; no consumer guard bypass or forced deletion.
2. Remote HelperCLI intentionally reports generic helper failure, not serialized
   Go ErrPartial. The real partial verification refused correctly. Harness now
   requires the recorded target verify refusal, `payloadImportAttempted=false`,
   no marker, plus a separate fresh claim/no-completion readback. Arbitrary
   transport/authentication errors cannot pass that predicate.
3. Explicit `--resume-recorded-run` requires fresh exact target UID checks and
   preserves only the original proven cancellation; it never imports onto that
   partial target. Native positive/retry/remount/partial checks are replayed.

These were test-harness corrections, not silent empty-volume fallback or runtime
repair. Actual original attempts are retained in the private ledger, including
the initial safe active-consumer refusal and remote verify failure.

### Evidence and cleanup

Private artifacts:
`/private/tmp/pvccopy-live-85f6c7da53d2ec8a-build/`:
`ledger.json`, `ledger.review.json`, exact manifests/type checks, command journals,
`build.json`, helper OCI archive and both binaries. Driver journal contains 1,122
commands, 180 exact-policy denial challenges and 22 live matched helper-binary
checks across the original attempts/replay; export archives are never recorded.
All fixture observations are metadata/hash only. No source payload dump or
credential material is saved on the host. Kubeconfig contents are never logged.

Second-run cleanup CONFIRMED for both namespace UIDs, exact own policy/binding
and reader role/binding. Four tracked dynamic PVs (source, original probe,
completed target and cancelled target) were confirmed gone. Replacement probe
had no allocated PV. No manual PV deletion or storage-driver change. Disposable
fixture bytes were removed; evidence/binaries/archive and local image-cache
artifacts remain available for review/reuse. Existing namespaces/apps unchanged.

This is real live filesystem verification on the isolated single-node local-path
cluster, NOT a MySQL/logical backup test, production storage certification,
authenticated daemon lease/end-to-end control-plane proof, or Environment Ready.
