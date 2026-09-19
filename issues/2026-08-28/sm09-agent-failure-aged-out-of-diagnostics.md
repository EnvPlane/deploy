# SM-09 Agent failure aged out of diagnostics

The lifecycle gate can wait four minutes for a redacted plan state. During that
interval normal Agent watcher output can move the original materialization
warning beyond the last 100 container log lines, leaving only the normalized
API error code in failure diagnostics.

## Resolution

Inspect a bounded 1000-line tail while retaining the existing JSON filter that
emits only warning/error level, message, and error fields.
