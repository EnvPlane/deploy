# Reviewed native source profile

The normal control-plane project reconcilers now prepare filesystem source grant
reviews before compile, from authenticated discovery and resourceReview selections.
Namespace/name/UID are discovered, not manually preset project names. Review ID
and fingerprint are independent of feature environment names.

The owner reviews a durable row in the existing tenant approval workflow. Only
the exact approved fingerprint may install canonical owned source policy/binding
and finite RBAC. Runner chart values contain pvcCopy.sources/fenceNames and explicit
allowRootHelpers. Admission policies are operator-held, not Helm release-owned.

Rendering preview offline:

```
go build -o /tmp/envplane-pvc-copy-source-profile ./apps/pvc-copy-source-profile
bash deploy/scripts/render-pvc-copy-source-profile.sh \
  --renderer /tmp/envplane-pvc-copy-source-profile --input reviewed-metadata.json
```

Build in the control-plane repo; call the wrapper from the EnvPlane workspace.
The input contains references only, never Secret values. The wrapper never runs
kubectl, applies grants, changes sources or claims that a fence is enforced.

Normal installer must already have reviewed exact policy/RBAC write/read authority
and exact Runner-SA impersonation for non-persisting proof. The constrained remote
installer profile does not automatically include those permissions; denial remains
a normal recovery error. No unrestricted cluster policy/grant permission is added.

Readback checks ownership, UID, complete relevant specs, policy observed generation
and type-checking. Four server-side negative Pod dry-runs per source must identify
the exact source policy/digest; a positive readonly helper must also succeed. The
controller persists only a metadata receipt and passes reviewed values into the
regular same-cluster/remote Runner renderers. Copy admission is rechecked by Runner.

Onboarding never labels an active source offline or stops its writers. Runtime
offline/consumer checks and target prepublication exclusivity remain mandatory;
neither profile installation nor copy success alone promotes workload Ready.

SQL client-only onboarding uses the same native review with exact discovered
PVC/workload/Service and app/backup-admin/CA Secret UIDs. No application-Pod exec
is granted: exec/delete are limited to the deterministic no-PVC client helper.
SQL root config init needs explicit owner opt-in. Mixed namespaces share one
policy allowing only the reviewed filesystem OR SQL helper, with every other
Runner Pod creation denied.

After readback and effective negative AND positive server dry-runs, the receipt
emits `pvcCopy.sourceFences`, `mysqlRestore.sourceFences` and exact approved
production refs. Both fence arrays bind installed policy/binding UIDs and raw-hex
full-spec hashes. The shared Runner SA downward-API env is emitted once for FS
or SQL, including SQL-only profiles. SQL-only production refs do not depend on
filesystem enablement. No client approval flags or Secret values are rendered.

Source UID/image rotation needs new review: install new Deny, prove its exact
negative message, retire only approved old binding UIDs, then prove positive
helper acceptance. Failed positive proof restores old scope and journals fresh
binding UIDs; policies are never switched to Ignore or deleted.

Kubernetes 1.37 CEL sizing fields are omitted only from the admission expression;
the worker still checks the complete helper spec before exec. Local CEL/parity,
chart render and drift checks do not prove live TLS/dump/restore success.
