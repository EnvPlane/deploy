# Publish a new project Agent chart for scoped Flux status

## Observed behavior

Umbrella `0.4.546` includes the new Agent image, but remote project Agents are
installed from immutable `envplane-agent` chart `0.2.32`. That chart predates
the `rbac.fluxStatus.environmentScoped` and `kustomizationNames` values, so
the project release cannot render `ENVPLANE_FLUX_STATUS_ENVIRONMENT_SCOPED`.
The new image alone cannot activate the scoped Flux collector.

## Expected behavior

Publish an immutable child chart version containing the scoped Flux-status
templates, then let the umbrella dependency release select that chart. Remote
project reconciliation must use the selected chart and render the new
environment variable plus exact-name GET RBAC.

## Codex implementation prompt

Bump `envplane-agent` chart semver after the scoped Flux-status template
change. Run the chart test suite, publish the child chart through the standard
workflow, and let the dependency-update workflow create/select the matching
umbrella release. Verify a remote project Agent has the scoped environment
variable and only exact Kustomization GET permissions.
