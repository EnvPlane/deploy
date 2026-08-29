# Umbrella GHCR package is not public

## Summary

The umbrella release workflow publishes and signs `ghcr.io/envplane/envplane`,
but a clean anonymous Helm pull receives HTTP 401. The package was created with
private visibility, so the workflow correctly stops before publishing the
GitHub Release and signed stable index.

## Impact

- The no-registration guided install cannot consume the umbrella chart.
- The signed stable release index cannot be published.
- The release remains incomplete even though the SM-09 lifecycle gate passes.

## Resolution

Set the existing `EnvPlane/envplane` container package visibility to public in
GitHub Packages. Keep `verify-anonymous-oci-artifacts.sh` after publication so
future releases fail closed if public access regresses.
