# Disposable PVC-copy live verification harness

Status: implementation in progress; live copy NOT RUN. No existing source data,
application workload, authentication, chart, profile or cluster policy changed.

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
