# SM-09 accepts unusable Docker Desktop credentials

## Symptom

The local private-registry materialization gate accepted a Docker config where
`auths.ghcr.io` was an empty object and credentials were provided only through
the Docker Desktop credential store. The generated Kubernetes pull Secret then
contained no usable GHCR credentials, so every private umbrella image failed
with anonymous `401 Unauthorized` pulls and Helm waited until timeout.

## Fix

Require a non-empty inline `auths.ghcr.io.auth` value before creating the
Kubernetes pull Secret. Docker credential helpers cannot be serialized into a
Kubernetes `dockerconfigjson` Secret by this harness.

## Verification

The gate now fails immediately with an actionable message when the local Docker
config cannot be used by Kubernetes.
