# First-run activation fixture can expire before UI installation

The SM-09 real-browser fixture was signed with a 20-second lifetime before
Playwright began the first-run flow. Cluster verification and the four guarded
wizard transitions can consume that window, causing activation installation to
be rejected as already expired. The test then waits for an expiration state
that can never be reached.

Use a 45-second fixture lifetime so the browser can install a valid activation
before exercising its expiry and free-quota recovery evidence.
