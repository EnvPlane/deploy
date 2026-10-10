# Release candidates must prove exact-source required CI

Defect: compatibility resolution treated successful artifact publication as
qualification and its already-current path skipped qualification entirely.
An older successful run could also conceal a pending/failed newer run. Refresh
overwrote the selected report before validating its source revision.

Implementation prompt: in deploy release selection only, require trusted
`.github/workflows/ci.yaml` push/main CI at each candidate's exact full SHA.
Require the latest run/attempt and required job success; reject missing,
pending, failed, skipped, unknown and unavailable status evidence. Retain all
immutable pins, digest verification, signing and predecessor compatibility.
Validate refreshed reports before replacing the input. Add deterministic
negative tests and enforce gate ordering before source/image selection.

Scope excludes consumer pin scripts, contracts publication, copy drivers,
live harnesses and cluster operations. No push before shared verification.

Status: implemented. Local verification on 2026-10-10:

- `python3 scripts/tests/test-component-ci.py`: 17 tests PASS. Covers exact SHA,
  latest run/attempt, required jobs, failed/pending/unknown/missing evidence,
  API errors, pagination, concurrent reruns, closed candidate/pin mapping,
  real shell success/refusal with mocked API and refresh preservation.
- `bash scripts/tests/release-on-main-contract.sh`: PASS.
- `bash scripts/tests/test-current-compatible-artifact.sh`: PASS.
- `bash scripts/tests/github-actions-pinned-contract.sh`: PASS.
- `bash -n` on all three changed shell scripts: PASS.
- Ruby YAML parsing on all three changed workflows: PASS.
- `git diff --check`: PASS.

GitHub job response shape was checked against the official attempt-specific
jobs API documentation. Mocked API results do not prove actual candidate
hosted CI. No Kubernetes operations, image/pin changes, or pushes performed.
The gate intentionally refuses a still-running required CI run; re-run
publication/release selection after CI succeeds instead of substituting a
publication result. Shared verification and push remain with main.
