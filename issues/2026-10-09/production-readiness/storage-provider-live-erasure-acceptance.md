# Storage provider deletion and erasure need live acceptance

Status: OPEN coverage prerequisite, not a reproduced deletion bug. Frozen candidate: 0.4.682.

Pass 4: 52 race-enabled storage tests/subtests passed with zero skips, including PostgreSQL RLS/CAS/lease restart, mutual TLS, signed exact-volume observations, independent certificate trust, replacement-root and symlink rejection. These use disposable SQL and local filesystem/HTTP fixtures. The verifier is read-only: accepting a signed statement is not execution or independent proof of physical erasure.

Verification prompt for Codex: after authenticated onboarding, create a disposable feature PVC on each supported production provisioner, write a recognizable test marker, capture exact namespace/PVC/PV/backend identities, and delete only the authorized fixture through the product. Observe PVC, PV and provider backend independently. Test Delete and Retain behavior and provider outage/recovery. Only mark secure erasure verified after an independently trusted, exact-volume certificate with the required method-specific audit evidence; plain deletion must remain unknown. Never infer backup/snapshot/replica destruction. Keep rollback copies explicitly unknown. Obtain scope authorization before destructive live actions; never touch base application volumes.

Acceptance: candidate-bound provider deletion and erasure records identify the provisioner, exact asset and evidence type; retained/unknown data is represented truthfully. Failure/replay/foreign identity cases remain denied. No actual provider erase was performed in this pass.
