# SM-09 API curl failures drop safe response evidence

## Problem

The SM-09 harness used `curl --fail` directly in read helpers. On a non-2xx
response curl exits with code 22 before the release log records the endpoint,
HTTP status, or the control-plane's redacted error object.

## Impact

A clean-install failure cannot be diagnosed from preserved redacted evidence;
operators see only curl's exit code.

## Resolution

Capture each API response in the disposable harness directory, explicitly
evaluate the HTTP status, emit only status/code/field/error metadata for
failures, and preserve a transport failure's curl status. Successful calls
retain their JSON stdout contract.
