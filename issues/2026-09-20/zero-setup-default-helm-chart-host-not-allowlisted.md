# Zero-setup default Helm chart host is not allowlisted

## Observed behaviour

On a clean umbrella 0.4.324 installation, Bootstrap prefilled Helm Direct with
`oci://ghcr.io/envplane/envplane-e2e-workload:0.1.0`. The project-scoped
Runner accepted the preflight command but returned
`helm_chart_reference_invalid` because `ghcr.io` was absent from its explicit
chart-host allowlist.

## Expected behaviour

The default public OCI chart supplied by the umbrella must be preflighted by a
new project Runner without an operator-provided registry Secret. Explicitly
configured non-default chart hosts must remain denied until an operator
allowlists them.

## Scope

- Add only `ghcr.io` to the umbrella zero-values project-executor allowlist.
- Keep registry credentials empty: host allowlisting is network policy, not
  authentication.
- Cover the invariant in the umbrella chart contract test.

## Codex implementation prompt

Update the EnvPlane umbrella defaults so the public default Helm Direct chart
host `ghcr.io` is included in `sameClusterProjectExecutors.helmAllowedChartHosts`.
Do not add image-pull or registry credentials. Add a focused contract test that
fails if the prefilled GHCR chart and its Runner host allowlist drift apart.
Run the umbrella chart package and Go contract tests, commit with an English
message, then validate a clean Bootstrap Runner preflight.
