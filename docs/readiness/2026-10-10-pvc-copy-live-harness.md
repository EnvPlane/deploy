# Disposable PVC-copy live verification harness

Status: harness implemented; authorized live fixture preflight BLOCKED by the
Runner source-fence CEL runtime error below. Actual payload copy NOT RUN. No
existing source data, application workload, authentication, chart, profile or
storage driver changed. Only new owned fixture namespaces/RBAC/fence were created.

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

### P1 acceptance blocker: optional CEL request field accessed unguarded

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

Local-only checks: ten Python mocked safety tests PASS; four Go host-driver
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
