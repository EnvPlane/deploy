# Retry transient OCI dependency downloads in umbrella chart tests

## Evidence

`TestPublishedUmbrellaMountsRevisionScopedInstallFlowManifest` failed while
Helm fetched `envplane-control-plane` from GHCR. The chart dependency build
failed with `read: connection reset by peer` from a signed GHCR blob URL, not a
chart validation or rendering error.

## Required implementation

Retry `helm dependency build --skip-refresh` a small, bounded number of times
only when its output identifies a transient transport failure. Preserve an
immediate failure for invalid dependency metadata, chart validation failures,
or other deterministic errors.

## Acceptance criteria

- A transient GHCR connection reset is retried with bounded backoff.
- Deterministic Helm dependency failures are not retried.
- The final test failure still includes Helm output for diagnosis.
