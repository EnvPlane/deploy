# Cross-repository release automation authentication

Component repositories publish immutable multi-architecture images, then send a
`repository_dispatch` event to `envpilot/deploy`. The deploy repository validates
that event and opens a pull request which pins the exact image digest in the
umbrella values. Neither path accepts mutable `main` or `latest` release pins.

## Preferred authentication: three scoped GitHub Apps

Use three different GitHub Apps. Install each App only on the explicitly listed
repositories, never organization-wide.

| Purpose | App installation permissions | Repository secrets |
|---|---|---|
| Cross-repository source checkout | Contents: Read-only; Metadata: Read. Install on `bootstrap`, `deploy` and `frontend` only. | In component repos that read sibling sources: `ENVPILOT_SOURCE_READ_APP_ID`, `ENVPILOT_SOURCE_READ_APP_PRIVATE_KEY` |
| Component dispatch | Contents: Read and write; Metadata: Read | In every runtime repo: `ENVPILOT_DEPLOY_DISPATCH_APP_ID`, `ENVPILOT_DEPLOY_DISPATCH_APP_PRIVATE_KEY` |
| Deploy PR bot | Contents: Read and write; Pull requests: Read and write; Metadata: Read | In `envpilot/deploy`: `ENVPILOT_DEPLOY_PR_APP_ID`, `ENVPILOT_DEPLOY_PR_APP_PRIVATE_KEY` |

The source-reader can only clone the listed sibling repositories. The dispatcher
can request a token for `deploy` only and can invoke
`repository_dispatch`; it cannot create a pull request. The PR bot private key
is stored only in `deploy`, where the receiving workflow creates the branch and
pull request. `actions/create-github-app-token` mints short-lived installation
tokens at runtime. Do not add either private key to a repository file, values
file, artifact, log, or workflow output.

The component workflows request only `Contents: read` from the source-reader
App and `Contents: write` from the dispatch App. The deploy workflow requests
`Contents: write` and `Pull requests: write` only from the PR App. These are
installation-token permissions, not broad repository `GITHUB_TOKEN` grants.

## Fine-grained PAT fallback

Use this only while an App is unavailable. Fine-grained PATs must be owned by a
dedicated bot account, expire on a documented schedule, and be restricted to
`envpilot/deploy` only.

| Fallback secret | Where stored | Required permissions |
|---|---|---|
| `ENVPILOT_SOURCE_READ_PAT` | Component repositories that read sibling sources | Contents: Read-only; Metadata: Read on only the required sibling repositories |
| `ENVPILOT_DEPLOY_DISPATCH_PAT` | Each runtime repository | Contents: Read and write; Metadata: Read; only on `envpilot/deploy` |
| `ENVPILOT_DEPLOY_PR_PAT` | `envpilot/deploy` | Contents: Read and write; Pull requests: Read and write; Metadata: Read |

The workflows log a warning whenever the PAT fallback is selected. A missing
App and PAT fails before any cross-repository API request. Never use a classic
PAT or an account-wide token.

## Trust boundary and rotation

- Publish workflows run only for trusted `push` events to `main` and protected
  release tags; they do not run on `pull_request` or `pull_request_target`.
- Each publish job checks the canonical repository name. Fork runs and manual
  runs for non-`main` refs are skipped before any secret-bearing step, so forked
  or untrusted workflow code cannot receive App keys or PATs.
- The deploy update workflow runs only for `repository_dispatch` and manually
  initiated runs by repository collaborators. It validates component,
  repository, full `sha-<40 hex>` tag, digest and source revision before editing
  values.
- Rotate App private keys by adding the replacement secret, validating a manual
  dispatch, then removing the old key. Rotate PATs by creating a replacement,
  validating it, and revoking the previous token immediately.
- Failed token minting normally means the App is not installed on `deploy`, its
  installation lacks the listed permission, or the App ID/private key pair does
  not match. HTTP 401 indicates an invalid or expired credential; HTTP 403
  usually indicates repository scope or permission failure; HTTP 422 indicates a
  rejected dispatch payload or duplicate PR branch.
- A source checkout failure points to `ENVPILOT_SOURCE_READ_*`; a dispatch
  failure points to `ENVPILOT_DEPLOY_DISPATCH_*`; and a PR creation failure
  points to `ENVPILOT_DEPLOY_PR_*`. Do not broaden a token to fix a diagnostic;
  correct the App installation or replace the matching fallback secret.

## Diagnostics

The component job fails after image publication if no dispatcher credential is
configured, so the missing values-update PR is visible immediately. The deploy
job emits only component, repository, immutable tag and digest in its PR body;
it never emits a token. Start by checking the `Select ... authentication` step,
then verify the GitHub App installation scope and the exact `repository_dispatch`
payload in the Actions UI.
