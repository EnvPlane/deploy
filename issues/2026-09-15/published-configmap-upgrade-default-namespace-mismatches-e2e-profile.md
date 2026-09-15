# Published ConfigMap upgrade E2E uses a namespace incompatible with its default profile

## Observed

Running `scripts/published-configmap-upgrade-e2e.sh` with the documented
`deploy/helm/envplane/values-e2e-local.yaml` leaves the singleton Agent and
Runner in `Init:0/1`. Their preflight resolves
`envplane-control-plane.envplane.svc`, while the script's default release
namespace was `envplane-configmap-upgrade-e2e`.

## Impact

The published upgrade and rollback check cannot complete with the repository's
standard disposable values profile, so it fails before exercising immutable
ConfigMap migration.

## Fix implemented

Align the script default namespace with the profile's `envplane` Service DNS.
Also explicitly enable the platform reconciler with the disposable Kind
`standard` StorageClass. The script asserts a revision-scoped reconciler status
ConfigMap, which cannot exist while all platform dependencies are disabled.
Preserve `ENVPLANE_CONFIGMAP_E2E_NAMESPACE` for callers using a
namespace-neutral custom values file.

## Verification

Run the script on a disposable Kind context with published `N-1` and `N`
umbrella archives. Verify install, server-side upgrade, rollback in both
directions, and uninstall complete without stale ConfigMaps.

## Codex implementation prompt

Review every published-artifact E2E harness that accepts a values file. Ensure
its default release namespace is either compatible with the repository's
default values profile or mandatory/explicit. Add a focused regression test or
preflight that prevents Service-DNS namespace mismatches before Helm waits for
workloads.
