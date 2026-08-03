# Automatic umbrella releases from `main`

Every trusted push to `envpilot/deploy` `main` starts
`.github/workflows/release-on-main.yaml`. The workflow builds a fresh,
immutable umbrella release; it does not commit generated pins back to the
repository.

The workflow resolves the newest published artifacts from GHCR using the
package API and verifies them before packaging:

- runtime images use a full `sha-<40-hex>` tag and the inspected multi-platform
  `sha256` digest for API, frontend, Agent, Runner and the platform reconciler;
- child charts use the highest published stable SemVer and are pulled from the
  canonical OCI repositories;
- the selected predecessor umbrella chart is pulled and its compatibility
  manifest is checked before the new release is announced.

The build workspace rewrites only its copy of `values.yaml`, `Chart.yaml`,
`Chart.lock` and vendored archives. The source chart directories remain the
canonical development sources. The resulting chart receives the next patch
SemVer, is linted/rendered/tested, signed with cosign, attested with a JSON
compatibility predicate, pushed to `oci://ghcr.io/envpilot/envpilot`, and
published as a GitHub Release with machine-readable metadata.

No mutable `latest` or `main` artifact is accepted. A missing package, invalid
digest, missing child chart, failed compatibility test, or occupied release
version stops the workflow before publication. The job needs the repository
`GITHUB_TOKEN` with `packages: write`, `contents: write`, `id-token: write` and
`attestations: write`; package visibility and Actions policy must allow that
token to read the EnvPilot GHCR packages.

The workflow is serialized with the umbrella release group. Component image and
child-chart publication workflows remain responsible for publishing their
immutable artifacts; this workflow consumes only artifacts that are already
available and verified in GHCR.
