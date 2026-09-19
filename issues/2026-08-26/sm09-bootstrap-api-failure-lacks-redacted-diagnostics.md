# SM-09 Bootstrap API failures lack redacted diagnostics

## Problem

The live harness used `curl --fail` for Bootstrap requests. On an API 400 it
reported only curl exit 22, so the contract error code or field was lost while
the Kind cluster was cleaned up.

This obscured the Bootstrap failure in [umbrella release run
33002789354](https://github.com/envplane/deploy/actions/runs/33002789354).

## Resolution

Capture each Bootstrap response in the disposable temporary directory and,
when a request fails, emit only its structured code, field, and error message.
The request payload contains references only; the harness never prints or
persists Secret values, envelope bytes, leases, or API tokens.
