# Cross-repository release automation authentication

Component repositories publish immutable multi-architecture images, then send a
`repository_dispatch` event to `envpilot/deploy`. The deploy repository validates
that event and opens a pull request which pins the exact image digest in the
umbrella values. Neither path accepts mutable `main` or `latest` release pins.

## Preferred authentication: one GitHub App

Use one private GitHub App named `envpilot-release-automation`. Install it on
`envpilot/bootstrap`, `envpilot/deploy`, `envpilot/frontend`,
`envpilot/control-plane`, `envpilot/agent` and `envpilot/runner`.
Control-plane and Runner also read the canonical bootstrap source. The deploy
receiver needs access to each runtime repository's private GHCR package to
verify a submitted immutable image digest before it changes umbrella values.
Give the installation these
permissions:

| Permission | Access | Why it is needed |
|---|---|---|
| Metadata | Read-only | Required by every installation token. |
| Contents | Read and write | Read the canonical deploy source, dispatch events and update the serialised automation branches. |
| Pull requests | Read and write | Create and request auto-merge for values and dependency update PRs; repository policy may leave them open for a normal protected merge. |
| Packages | Read-only | Verify immutable GHCR manifests from the runtime repositories before creating a values PR. |

No webhook, organization administration, Actions, secrets, workflows, issues or
checks permission is required. Runtime publishing continues to use its own
short-lived `GITHUB_TOKEN` for writing the component image package only; the App
is read-only for Packages.

Store the App credentials as Actions secrets, never in a repository file,
values file, artifact, log or workflow output:

| Secret | Where stored |
|---|---|
| `ENVPILOT_AUTOMATION_APP_CLIENT_ID` | `frontend`, `control-plane`, `agent`, `runner` and `deploy` repositories |
| `ENVPILOT_AUTOMATION_APP_PRIVATE_KEY` | The same five repositories |

Component workflows mint two short-lived tokens from this same App: a
`contents: read` token for the additional deploy source checkout and a
`contents: write` token for `repository_dispatch`. Deploy workflows mint a
`contents: write`, `pull-requests: write`, `packages: read` token only inside
trusted receiver jobs to verify the source package, update the automation branch
and create a PR. The private key is never made available to pull-request or
fork-triggered workflows.

## Fine-grained PAT fallback

Use `ENVPILOT_AUTOMATION_PAT` only while the App is unavailable. Store it in the
same five repositories. It must belong to a dedicated bot account, expire on a
documented schedule, be limited to `envpilot/deploy`, and have only Contents and
Pull requests read/write access. The workflows emit a warning whenever this
fallback is selected. Never use a classic PAT or an account-wide token.

## App setup and rotation

1. Create the private App in the `envpilot` account, grant Packages read-only,
   and install it on `bootstrap`, `deploy`, `frontend`, `control-plane`,
   `agent` and `runner`.
2. Generate a private key once, add its ID and PEM to the two named secrets in
   each listed repository, then securely delete the downloaded PEM file.
3. Run a manual publish in one component and confirm that `deploy` receives a
   dispatch and creates or refreshes the corresponding PR.
4. Rotate by generating a second App key, replacing
   `ENVPILOT_AUTOMATION_APP_PRIVATE_KEY` in all five repositories, validating a
   manual dispatch, and revoking the old key. Rotate the fallback PAT by
   replacement then immediate revocation.

GitHub only returns the private key at generation time. Treat its loss as a key
rotation event, not as a request to recover or log it.

## Trust boundary and diagnostics

- Publish workflows run only for trusted `push` events to `main` and protected
  release tags; they do not run on `pull_request` or `pull_request_target`.
- Canonical repository checks run before any token-bearing checkout. Fork runs
  and non-`main` manual runs are skipped before App secrets are read.
- The deploy receiver validates component, repository, full `sha-<40 hex>` tag,
  digest and source revision before changing values.
- A token-mint failure normally means the App is not installed on `deploy`, its
  permissions are insufficient, or the ID/key pair does not match. HTTP 401 is
  an invalid or expired credential; HTTP 403 is scope or permission failure;
  HTTP 422 is a rejected dispatch payload or duplicate PR branch.
- The component job fails after image publication when neither App nor fallback
  is configured, making a missing values-update PR visible immediately.

Start diagnosis with the `Select ... authentication` step, then verify the App
installation scope and the exact `repository_dispatch` payload in Actions.
