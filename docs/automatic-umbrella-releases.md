# Automatic umbrella releases from `main`

Successful `Publish deploy image and charts (main)` runs trigger
`.github/workflows/release-on-main.yaml` (or it can be dispatched with an
artifact run ID). The workflow builds a fresh,
immutable umbrella release; it does not commit generated pins back to the
repository.

The workflow consumes the confirmed compatibility report for the selected
deploy main SHA, not the newest available package. Before source checkout or
image selection, `scripts/validate-release-gate.sh --report <report>` requires
each exact candidate SHA to pass trusted push/main `.github/workflows/ci.yaml`
CI. API, frontend, Agent, Runner and webhook map to their own repositories;
the platform reconciler and all child-chart sources map to deploy. The latest
CI run and exact attempt must complete successfully, including `test` (or
deploy's `helm`) and all returned jobs. Missing, pending, failed, skipped,
neutral, unknown, changing or unavailable status evidence fails closed. An
older green run or successful image publication is not CI proof. Publication
resolution also qualifies the pinned image SHAs before registry selection.

The gate uses GitHub CLI and bounded, paginated Actions API reads. Workflows
use the automation PAT when configured, otherwise the workflow token for
public component repositories. Private repositories require read access to
Actions for every selected repository; permission or service errors refuse
selection rather than fall back. No new write permission is needed. Legacy
YAML release manifests remain supported, now requiring exact tested-artifact
CI as well as their original structural checks. Local mocked tests are not
hosted-CI evidence. Unqualified refreshes leave the original report intact.
Attempt identity comes from GitHub's [attempt-specific jobs endpoint](https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run-attempt),
not an assumed `run_attempt` field in each job response.

Immutable artifacts are separately verified before packaging:

- runtime images use a full `sha-<40-hex>` tag and the inspected multi-platform
  `sha256` digest for API, frontend, Agent, Runner and the platform reconciler;
- child charts use the source tree's pinned stable SemVer and are pulled from the
  canonical OCI repositories;
- the selected predecessor umbrella chart is pulled and its compatibility
  manifest is checked before the new release is announced.

The build workspace rewrites only its copy of `values.yaml`, `Chart.yaml`,
`Chart.lock` and vendored archives. The source chart directories remain the
canonical development sources. The resulting chart receives the next patch
SemVer, is linted/rendered/tested, signed with cosign, attested with a JSON
compatibility predicate, pushed to `oci://ghcr.io/envplane/envplane`, and
published as a GitHub Release with machine-readable metadata.

No mutable `latest` or `main` artifact is accepted. A missing package, invalid
digest, missing child chart, failed compatibility test, or occupied release
version stops the workflow before publication. The job needs the repository
`GITHUB_TOKEN` with `packages: write`, `contents: write`, `id-token: write` and
`attestations: write`; package visibility and Actions policy must allow that
token to read the EnvPlane GHCR packages.

The workflow is serialized with the umbrella release group. Component image and
child-chart publication workflows remain responsible for publishing their
immutable artifacts; this workflow consumes only artifacts that are already
available and verified in GHCR.
