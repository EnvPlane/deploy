# AUD-009: Saving unchanged components invalidates all SCM proofs

Status: confirmed by source audit; not fixed.
Priority: P2
Estimated effort: S

## Evidence

frontend/components/bootstrap/BootstrapWizardClient.tsx:3748-3763; control-plane/internal/server/server_projects.go:782-803

No-op save or service-mapping edit clears component validation, global fingerprint and GitOps writable proof. Encrypted credentials can be reused, but users still repeat unnecessary validation.

## Implementation prompt for Codex

Make semantic no-op saves idempotent. Invalidate only affected repository/branch/credential proofs; keep service mapping validation independent. Test unchanged, mapping-only, repo-changing and auth-changing saves.

Commit verified iterations with English messages. Distinguish local tests from live acceptance.
