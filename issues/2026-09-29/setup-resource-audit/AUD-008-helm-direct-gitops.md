# AUD-008: Connected Helm Direct requires an unnecessary writable GitOps repository

Status: confirmed by source audit; not fixed.
Priority: P2
Estimated effort: M

## Evidence

frontend/components/bootstrap/BootstrapWizardClient.tsx:1834-1840,4211; control-plane/internal/app/scm_validation_service.go:523-531

SCM is gated before backend selection; validation always requires writable GitOps. Offline mode is not an equivalent substitute for connected Helm deployments.

## Implementation prompt for Codex

Select backend before SCM requirements; derive required repositories and access modes from actual features. Test connected Helm Direct with readable application SCM only and Flux with required writable GitOps. Preserve webhook and application build capabilities.

Commit verified iterations with English messages. Distinguish local tests from live acceptance.
