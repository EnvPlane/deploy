# EP-SSO-018 anonymous clean install is blocked by private runtime images

The existing disposable clean-cluster harness
`scripts/private-registry-secret-materialization-e2e.sh` requires an inline
GHCR credential from `~/.docker/config.json` and creates the
`release-registry-pull` Secret for every umbrella runtime.

This violates EP-SSO-018's anonymous Helm-install acceptance criterion. A
repository-only change cannot make the required GHCR packages public or move
their immutable runtime images to a public anonymous registry.

## Required external remediation

- Make every image selected by the signed umbrella compatibility manifest
  anonymously pullable, including both supported architectures; or
- publish the signed immutable release set to an equivalent public registry
  and update the release manifest/index to that public location.

After this is complete, replace the GHCR Docker-config precondition in the
clean-cluster harness with `verify-anonymous-oci-artifacts.sh` and prove a
fresh node pulls all runtime images without `imagePullSecrets`.
