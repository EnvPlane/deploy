# Render a disabled writer mode for empty managed remote targets

## Evidence

The managed remote chart contract allows no target namespaces when
`featureEnvWriter.enabled=false`, but the deployment still exports
`preconfiguredNamespaces` to Runner. That mode requires a non-empty list and
causes a runtime configuration failure before registration.

## Implementation prompt

When feature writer is disabled, render `ENVPLANE_FEATURE_ENV_WRITER_MODE` as
`disabled` and no writable namespaces. Keep the precise namespace modes for
enabled writers. Add a chart contract test for managed remote zero targets.

## Acceptance criteria

- A managed remote release with no targets renders a disabled writer mode.
- It does not render a preconfigured empty namespace list.
- Enabled writer releases keep their exact namespace contract.
