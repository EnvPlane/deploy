# Long release names truncate the revision from platform reconciler status ConfigMaps

## Observed

The chart generated the status name by truncating the complete string:
`<release>-platform-dependency-reconciler-status-r<revision>`. With release
`envplane-configmap-upgrade-e2e`, both revision 1 and revision 2 were reduced
to `envplane-configmap-upgrade-e2e-platform-dependency-reconciler-s`.

## Impact

The platform reconciler writes `status.json` to a ConfigMap that Helm owns.
The next server-side upgrade cannot create a fresh status object, reintroducing
the exact field-ownership conflict that revision-scoped names are intended to
avoid.

## Fix implemented

The chart reserves a compact `-pdr-status-r<revision>` suffix before
truncating the release-name prefix. The revision is therefore retained for all
valid Kubernetes resource names. E2E helpers now calculate the same name.

## Verification

Render a 53-character release name at revisions 1 and 2 and assert different,
DNS-valid status ConfigMap names ending in `-r1` and `-r2`. Run the published
upgrade/rollback E2E with a healthy predecessor.

## Codex implementation prompt

Audit all Helm helpers that append generation or revision identifiers before a
generic `trunc 63`. Change them to reserve a compact unique suffix first, add
long-release-name regression coverage, and update any harnesses that compute
the resource name independently.
