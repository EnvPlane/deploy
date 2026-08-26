# SM-09 live envelope and Agent-auth negative cases

## Status

Resolved on 2026-08-26.

## Problem

The clean-cluster harness now proves foreign-target rejection with the real
Agent. The other requested live negatives cannot yet be truthfully exercised:

- Agent runtime identity is held in the Agent Pod and no test-safe lease
  administration operation exists; the harness must not extract or print it.
- `encrypted_clone` currently passes a stable envelope reference but consumes
  no tenant-scoped envelope/lease store, so tampering would not affect the
  production data path.
- Bootstrap compilation does not retain a signed scan allowlist that can
  reject a source-namespace escape at dispatch time.

## Resolution

The v2 shared command contract carries metadata-only, audience-bound envelope
leases with signed digests and expiry. The control plane issues and validates
them, encrypted-clone source namespaces are part of the canonical signed plan,
and the Agent revalidates leases at execution time. Explicit release-test
faults are disabled by default and enabled only in the disposable harness.
The atomic gate now covers wrong tenant, expired lease, tampered envelope,
namespace escape, foreign target, and Agent restart.
