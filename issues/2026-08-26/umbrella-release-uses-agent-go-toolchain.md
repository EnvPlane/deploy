# Atomic umbrella release retains the Agent Go toolchain

The release workflow selects Go from the release-compatible Agent to run the
Secret materialization gate, then later runs the deploy chart tests with the
same `GOTOOLCHAIN=local` setting. Deploy now requires Go 1.26.6 while the
published Agent uses Go 1.25.13, so packaging fails after the lifecycle gate.

## Resolution

Select the deploy repository Go toolchain again immediately before validating
and packaging the umbrella chart.

## Status

Resolved in the coordinated Secret materialization release.
