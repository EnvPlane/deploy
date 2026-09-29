# AUD-014: Offer a supported durable credential mode without one PVC per runtime

Status: architecture opportunity; not implemented.
Priority: P3
Estimated effort: L

## Evidence

deploy/deploy/helm/envplane-agent/values.yaml:121-147; deploy/deploy/helm/envplane-runner/values.yaml:89-111; deploy/deploy/helm/envplane-agent/templates/auth-pvc.yaml:1; deploy/deploy/helm/envplane-runner/templates/auth-pvc.yaml:1

Architecture improvement, not a confirmed default-mode bug. Agent and Runner each request an auth PVC by default, adding two PVCs per project runtime pair and a StorageClass dependency. Existing Secret mode still leaves createClaim enabled unless manually disabled. Durable one-time-token exchange state is necessary; simply removing PVCs is unsafe.

## Implementation prompt for Codex

Specify mutually exclusive supported credential persistence modes (managed durable state, external Secret, PVC). Measure cloud minimum-volume cost and startup/storage dependency. Preserve restart recovery, replay protection and tenant scoping; offer automatic mode selection only with explicit guarantees. Keep isolated project identities rather than merging all executors.

Commit verified iterations with English messages. Report local tests and live verification separately.
