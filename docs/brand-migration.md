# EP-BRAND-002: Helm and Kubernetes naming migration

The canonical user-facing product name is EnvPlane. This migration does not
rename live Kubernetes objects in place: the current `envpilot` chart names,
release names, OCI coordinates and `envpilot.io/*` ownership labels are part of
the compatibility contract for existing installations.

## Inventory and ownership

| Surface | Current compatibility identifier | Migration rule |
| --- | --- | --- |
| Umbrella chart/release | `envpilot`, `envpilot-*` | Keep stable for in-place upgrade; a future `envplane` chart is a separately versioned migration. |
| Namespaces | `envpilot`, `envpilot-executors` | Never rename automatically; create a new namespace only through an explicit migration. |
| Workload selectors | `app.kubernetes.io/name=envpilot-*`, component selectors | Immutable in place; changing them would orphan Deployments/Services. |
| Stateful resources | `*-postgres`, `*-redis`, `*-data` PVCs | Keep names and claims stable; backup/restore before any future rename. |
| ServiceAccounts/RBAC | release-derived `envpilot-*` names and resourceNames | Keep stable; RBAC migration must bind old and new identities before cutover. |
| Secrets/ConfigMaps | managed auth, registration, compatibility and status names | Keep stable; Secret data is never copied by Helm. Revision-scoped ConfigMaps remain immutable inputs. |
| OCI charts/images | `oci://ghcr.io/envpilot/envpilot-*`, `ghcr.io/envpilot/*` | Keep published coordinates; publish any `envplane` coordinate as an additional artifact first. |
| Values/env keys | `global.envpilot.*`, `ENVPILOT_*` | `global.envplane.*` and `ENVPLANE_*` are canonical; canonical values win. |
| Human-readable docs/UI | legacy product spelling | Use EnvPlane; machine compatibility names may remain in code examples where required. |

## Values compatibility

The umbrella and child charts accept a canonical `global.envplane` tree. It is
recursively merged over the legacy `global.envpilot` tree, so a value supplied
in both places is taken from `global.envplane`. Existing values files continue
to render unchanged. The same rule applies to runtime `ENVPLANE_*` aliases in
the control-plane image.

Example:

```yaml
global:
  envpilot:
    auth:
      mode: legacy_secret
      existingSecret: old-auth
  envplane:
    auth:
      mode: disabled
```

This renders the disabled mode while preserving all unrelated legacy values.
It does not create, delete, or rename a Secret.

## Upgrade and rollback

1. Render and diff the target chart; verify selectors, PVC names, Secret names,
   ServiceAccounts and RBAC `resourceNames` are unchanged.
2. Upgrade the existing `envpilot` release with canonical values. Helm owns the
   same objects and can roll back to the prior chart revision.
3. Keep the prior OCI chart and compatibility manifest available until the new
   revision is Ready. Do not delete old resources as part of branding work.
4. Roll back with `helm rollback <release> <revision>` if readiness or smoke
   checks fail; canonical values can be removed because legacy values remain
   accepted during the migration window.

No new OCI artifact or release is published by EP-BRAND-002. A future rename
requires a separate, explicitly approved release containing a dual-resource
cutover and a tested rollback path.
