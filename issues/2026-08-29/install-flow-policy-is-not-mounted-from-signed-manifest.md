# Install-flow policy is not mounted from the signed manifest

The umbrella compatibility manifest now declares first-run and activation
contract versions plus rollout policy. The control-plane chart does not yet
mount that signed declaration, so a values-only rollout setting cannot be
checked against the selected release contract at runtime.

## Required remediation

- Render an immutable revision-scoped ConfigMap from
  `compatibility/release.json` for every published umbrella release.
- Mount it read-only into control-plane and reject a mode or contract mismatch
  before first-run or activation state is mutated.
- Keep the previous revision-scoped ConfigMap available through Helm rollback.
- Add chart rendering and upgrade/rollback regression coverage.
