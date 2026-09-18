# SM-09 release gate leaves kubectl on a deleted Kind context

## Evidence

Running `scripts/private-registry-secret-materialization-e2e.sh` creates a
Kind cluster. `kind create cluster` selects that context in kubeconfig, while
the cleanup trap deletes the cluster without restoring the caller's previous
context. Subsequent ordinary `kubectl` commands fail with a connection error
to the deleted local API server.

## Expected behaviour

The disposable release gate must leave the caller's kubeconfig context exactly
as it was before the script began, on success and on failure.

## Implementation prompt for Codex

Capture `kubectl config current-context` before creating the Kind cluster. In
the cleanup trap, after deleting only the disposable Kind cluster and registry,
restore that context when it still exists. Do not override a missing context or
fail cleanup when restoration is unavailable. Add a release-contract assertion
that prevents removal of both capture and restoration logic.

## Acceptance criteria

- The SM-09 script restores a valid pre-existing kubecontext after cleanup.
- Cleanup remains best-effort and redacts credentials.
- `bash scripts/tests/release-on-main-contract.sh` proves the guard exists.
