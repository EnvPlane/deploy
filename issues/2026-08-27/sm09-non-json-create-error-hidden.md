# SM-09 hides non-JSON create failures

## Problem

The private-registry lifecycle harness assumes every unsuccessful API response
is a JSON object. A non-JSON response causes `jq` itself to fail, hiding the
HTTP status and response type that identify whether the failure came from the
API handler, HTTP mux, proxy, or connection layer.

Runner diagnostics are also absent from the failure trap, even after create
has switched from local execution to Runner command dispatch.

## Expected behavior

The harness must report status, content type, and body size for non-JSON
responses without printing the body. It must include only structured,
redacted Runner warnings and errors in failure diagnostics.
