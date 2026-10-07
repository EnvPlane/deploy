# Explicit local-development storage installation profile

Status: implemented; Helm opt-in/permission/conflict/drift tests passed.

Codex prompt: bundle the reviewed digest-pinned local-path manifest in umbrella
with localDevelopmentStorage.enabled=false and allowHostPath=false. Require
explicit administrator approval; reject a simultaneous managed storage installer.
Keep envplane-local-path non-default and project runtime privileges unchanged.
Keep all provisioner objects across application uninstall until a separate
administrator cleanup confirms no owned PVs remain.
Test default render omission, explicit guard, pinned image identities and exact
parity with platform/local-storage/local-path.yaml. Document that Helm installs
in its target context only, not in arbitrary connected remote clusters.
