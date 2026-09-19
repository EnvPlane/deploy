# EP-SSO-018 anonymous clean install is blocked by private runtime images

The existing disposable clean-cluster harness
`scripts/private-registry-secret-materialization-e2e.sh` requires an inline
GHCR credential from `~/.docker/config.json` and creates the
`release-registry-pull` Secret for every umbrella runtime.

This violated EP-SSO-018's anonymous Helm-install acceptance criterion.

## Resolved

On 2026-08-29, `ghcr.io/envplane/envplane:0.4.140` and every selected signed
child/image artifact were pulled with an isolated empty Docker and Helm
credential store. The SM-09 harness no longer creates a GHCR
`imagePullSecrets` object or reads a host Docker config; it retains only the
generated disposable source Secret needed to test encrypted clone.

The release gate now proves a fresh node pulls all runtime images without
`imagePullSecrets`.
