# SM-09 same-cluster HTTP preflight not enabled

## Problem

The disposable Kind profile uses the in-cluster control-plane HTTP Service.
The Agent runtime endpoint probe correctly treats HTTP as local-development
only, but the profile did not opt in. The Agent therefore reported degraded
and intentionally skipped resource-scan task processing.

## Resolution

Set `envplane-agent.controlPlane.allowInsecure=true` only in the disposable
E2E profile. Remote Agent charts retain their HTTPS-only default and cannot
receive this setting from the SM-09 profile.

## Verification

Render the local E2E umbrella profile and confirm the Agent receives
`ENVPLANE_ALLOW_INSECURE_CONTROL_PLANE=true`, then run the private-registry
lifecycle gate.
