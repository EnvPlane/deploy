# Remote runtime PVC labels and discovery preflight

## Observed in E2E

Remote Agent installation failed atomically because the published chart placed
full `sha256:` compatibility and trust revisions in PVC labels. Kubernetes
labels accept at most 63 characters, while the values are 71 characters.
The same reconciliation also reported a configured discovery namespace that
does not exist on the target cluster.

## Required implementation

1. Keep the full managed-remote lifecycle contract in annotations, not labels.
2. Limit PVC labels to safe fixed selectors and preserve all lifecycle values
   in annotations for audit and rollout changes.
3. Keep remote runtime namespace creation scoped to Agent/Runner namespaces;
   do not create user application discovery namespaces implicitly.
4. Add a preflight/status diagnostic that identifies every configured discovery
   namespace absent from the target cluster before Helm install is attempted.
5. Cover both Agent and Runner chart rendering, and the remote reconciliation
   preflight, with regression tests.

## Acceptance criteria

- A managed remote Agent/Runner release accepts full sha256 compatibility and
  trust values without producing an invalid Kubernetes label.
- PVC annotations retain the exact values.
- A missing discovery namespace is reported as an actionable prerequisite,
  without granting namespace creation permissions beyond runtime namespaces.

## Release packaging follow-up

Any change under a published child chart must increment that chart's semantic
version and update the umbrella dependency pin. Otherwise a new umbrella
release resolves the previously published immutable child artifact and omits
the fix. This incident requires Agent `0.2.25` and Runner `0.4.8` before the
next umbrella release is created.
