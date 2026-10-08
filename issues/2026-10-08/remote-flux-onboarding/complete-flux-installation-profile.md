# Complete Flux installation profile for future environment names

Priority: P1
Status: implemented locally; not pushed or applied.

## Evidence

On umbrella 0.4.677, e2e-flux-auto-677-1008678 failed before publication because the installed exact-name installer parent omitted the new Kustomization. The renderer already offered a separate opt-in delegation flag, but the basic installation command did not express a complete Flux deployment profile.

## Implementation prompt

Make Flux status delegation part of an explicitly selected Flux installation profile, with a configurable control namespace and arbitrary project/environment IDs. Keep non-Flux defaults unchanged, preserve exact-name project Agent Roles, and never auto-expand stored credentials. Validate the emitted namespace/installer identity and get-only rule, repeated options, unsupported modes and invalid namespaces. Explain the one-time migration for existing installations before retrying provisioning.

## Implementation

`--deployment-backend fluxcd` now includes the dynamic status parent automatically, using `flux-system` or `--flux-control-namespace NAME`. Existing standalone `--flux-status-reader-namespace` remains supported and is deduplicated. Default Helm Direct grants no new Flux access. The parent gives the installer get-only Kustomization metadata in the selected namespace, including other projects' metadata; project Agents retain exact resourceNames. No Secret/list/watch/mutation grants are added by the mode. It does not supply the separate GitOps source-writer permission.

API denial guidance now identifies the complete profile and keeps the exact-object fallback. The profile must be reviewed/applied once by an administrator: source changes cannot authorize an existing restricted ServiceAccount to grant rights it does not hold.

## Verification

Renderer shell contracts and Go RBAC-object tests pass for default/custom Flux namespaces, arbitrary IDs, installer subjects, exact get-only rules, duplicate elimination and invalid options. Scoped server Flux access tests, brand and diff checks pass. No live RBAC migration or deployment was performed. The existing Failed test remains pending migration/retry.
