# AUD-005: New profile lacks discovery-parent bindings and identity parity

Status: confirmed by source audit; not fixed.
Priority: P1
Estimated effort: M

## Evidence

deploy/scripts/render-remote-cluster-rbac-profile.sh:29,145-198,227-285; control-plane/internal/server/remote_project_reconciler.go:465; control-plane/internal/app/remote_cluster_access_validator.go:165-175,297-309

Renderer allows custom ServiceAccount but project namespace reconciler binds the fixed envplane-remote-cluster-ID subject. Static runtime/base namespaces receive runtime-manager but no discovery-parent binding: the installer lacks read resourcequotas/limitranges/HPA/Flux permissions needed to create Agent discovery Roles under Kubernetes escalation checks. Preflight omits discovery namespaces and these permissions.

## Implementation prompt for Codex

Unify renderer, saved credential identity and preflight into one permission contract. Either remove unsupported SA override or persist and use it everywhere. Bind bounded discovery parent where required. Test clean install under the generated credential with arbitrary IDs and a finite base namespace set.

Implement in the relevant child repositories. Preserve existing installations and tenant isolation. Commit each verified iteration with English messages. Report local, CI and live results separately.
