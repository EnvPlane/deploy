# New feature provisioning blocked by legacy exact-name Flux installer grants

Status: live reproduced; exact administrative get grant approved and applied;
retry/recreate succeeded. Broader installer-profile migration remains opt-in.

On release 0.4.652 UI created e2e-ui-full-652-1007652 for project app, branch main,
MR 1007652, Full mode, project-default TTL 24h, with no changed components.
The record became Failed before workload publication. Bootstrap identifies:
target Flux status-reader delegation denied: get kustomizations in flux-system
for e2e-ui-full-652-1007652.generic. Target Agent/Runner remain healthy.

This is the previously scoped installer-profile migration boundary, reproduced
with a fresh name. Prior permissions for another exact test name do not
authorize namespace-wide read access. Request only the new exact get permission
for this test; do not silently install the optional broader get-only profile.

Codex prompt: verify the existing scripts/render-remote-cluster-rbac-profile.sh
--flux-status-reader-namespace profile and preflight behavior. Distinguish
old exact-object grants from a profile supporting arbitrary future feature
names. Show that limitation before presenting unconditional deploy readiness.
Keep all migration actions explicitly administrator-approved and do not grant
Secret/list/watch or write permissions as a readiness workaround. Add tests
for exact-name legacy profiles and namespace-scoped get-only status delegation.

The user approved only get for this exact Kustomization. Patched the existing
envplane-project-app-feature-flux-reader-parent Role using UID/rule test
preconditions; the other four exact object names and get-only verbs were
preserved. can-i changed from no to yes. Bootstrap Retry executor provisioning
returned Deploy-ready. UI Recreate was accepted and the environment became
Ready with three services, three Running/Ready Pods and two Bound feature PVCs.

Scoped cleanup passed after explicit action-time approval. UI Delete reached
Terminated. The namespace, exact Flux Kustomization and both feature PVs are
absent. Both exact backing paths are absent, including dangling symlinks.
Base backend/frontend/MySQL Pods remain Ready and base PVCs remain Bound with
their original volume identities. Terminated history was intentionally retained.
Remaining acceptance: browser preview DNS; no reachable domain supplied yet.
No namespace-wide get, Secret access, base-resource change or broad RBAC grant
was used. Patch audit: /private/tmp/envplane-flux-read-1007652-patch.json.
