# Activation verification configuration is not mounted by the chart

The control-plane accepts `ENVPLANE_ACTIVATION_PUBLIC_KEYS_JSON` and an
optional issuer metadata endpoint, but the control-plane Helm chart did not
render either value. A deployment therefore could not verify a valid signed
activation code without an out-of-band Pod mutation.

## Resolution

The chart now exposes only public verification-key metadata and the optional
issuer URL through the `license` values block. The chart contract verifies
both environment variables and rejects any issuer private-key material.
