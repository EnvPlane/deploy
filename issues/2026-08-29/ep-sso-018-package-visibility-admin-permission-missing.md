# EP-SSO-018 package visibility cannot be remediated with current GitHub token

The current GitHub CLI token has `repo`, `workflow`, `read:org`, and `gist`
scopes, but no `read:packages` or package-admin permission. GitHub rejects
even the organization container-package listing endpoint with HTTP 403.

Making the runtime images anonymously pullable requires an organization/package
administrator to change the selected GHCR packages' visibility, or to configure
an approved public registry mirror. This cannot be completed by a source-code
patch or by the current credential.
