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

SQL client-only onboarding is not shipped by this filesystem profile. It rejects
SQL requests rather than granting obsolete app-Pod exec. SQL needs a reviewed
no-PVC helper policy, exact app/backup-admin/CA refs and explicit root-init opt-in.
Mixed source namespaces require a shared combined fence verifier; separate policies
cannot override the existing filesystem Runner-create restriction. Source UID/image
rotation requires new review; retiring overlapping old authority is operator-held
until the reviewed transition proof/UID-precondition path is implemented.
