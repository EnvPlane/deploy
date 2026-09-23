# Publish updated control-plane chart for the remote Helm host allowlist

## Evidence

The umbrella release gate failed in `TestUmbrellaInjectsDefaultHelmDirectBootstrapChartWithoutInstallingIt`: its OCI dependency `envplane-control-plane:0.3.56` omitted `ENVPLANE_REMOTE_PROJECT_HELM_ALLOWED_CHART_HOSTS`. The local canonical chart source contained the field, so source-only CI passed while release packaging failed.

## Codex implementation prompt

Bump the immutable control-plane chart version and the umbrella dependency pin together, rebuild the chart lock and vendored archive, and test the OCI-equivalent packaged artifact before release. Do not mutate or republish chart version `0.3.56`. Keep the release gate asserting the runtime allowlist value `ghcr.io`.

## Resolution

Prepared control-plane chart `0.3.57` and matching umbrella dependency for publication. The release workflow can then select the newly published OCI chart rather than stale `0.3.56`.
