# EP-SSO-018 package visibility cannot be remediated with current GitHub token

The current GitHub CLI token has `repo`, `workflow`, `read:org`, and `gist`
scopes, but no `read:packages` or package-admin permission. GitHub rejects
even the organization container-package listing endpoint with HTTP 403.

## Resolved

The supplied `githubToken.txt` token has `write:packages` and package-admin
access. The selected EnvPlane packages are already public, including umbrella,
all runtime images, and child charts. An isolated empty Docker/Helm credential
store successfully pulled the latest published signed umbrella release.
