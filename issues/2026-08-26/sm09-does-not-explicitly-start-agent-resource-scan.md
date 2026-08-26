# SM-09 must explicitly start the Agent resource scan

The harness waited for a fixture scan without proving Agent and Runner
registration or requesting it. Wait for both runtimes, start the scan through
the authenticated Bootstrap API, and then wait for completion.
