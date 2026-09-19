# SM-09 API diagnostic must retain an error response

## Problem

The initial diagnostic wrapper still delegated to `curl --fail`, which omits
the HTTP error response body before `jq` can extract the redacted error.

## Resolution

The wrapper now saves the response, checks the HTTP status explicitly, and
prints only structured diagnostic fields on a non-2xx response.
