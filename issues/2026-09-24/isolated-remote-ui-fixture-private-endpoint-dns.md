# Provision private management endpoint DNS in the isolated Remote Cluster UI fixture

## Evidence

The temporary Kind target cluster used for the live Remote Cluster UI case did
not resolve the private management endpoint hostname. Agent preflight failed
until the fixture's CoreDNS configuration received an explicit, target-only
mapping to the management Kind control-plane IP. The target also needed its
configured base and feature discovery namespaces to exist before onboarding.

## Impact

The Remote Cluster UI scenario depends on manual, environment-specific setup
even though the management endpoint, target credential, and expected
discovery namespaces are already known by the test fixture.

## Implementation prompt

Add an isolated-only fixture helper that accepts explicit management and target
Kind contexts, provisions the named discovery namespaces, and installs an
idempotent CoreDNS host mapping for the supplied private management endpoint.
It must never change a user cluster or any context that was not passed
explicitly, and must remove only its own fixture resources during cleanup.

## Status

Open. The current live run was prepared manually and the target reconciled
healthy.
