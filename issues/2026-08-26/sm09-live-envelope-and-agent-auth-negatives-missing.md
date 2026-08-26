# SM-09 live envelope and Agent-auth negative cases are not executable

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

## Required follow-up

Wire `encrypted_clone` through the SM-04 envelope store, persist the scanned
source allowlist with the signed plan, and provide a non-secret Agent-auth
lease test control. Then add wrong-tenant, expired-lease, tampered-envelope,
and namespace-escape assertions to this harness.
