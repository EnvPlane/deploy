# SM-11 incorrectly requires a preview URL for a route-less fixture

Status: fixed locally; full release gate must confirm in CI.

The real browser creation test passed, and the API returned status ready with
an empty URL. SM-11 then timed out requiring a non-empty URL. The workload
fixture contains a Deployment and internal Service, without Ingress/HTTPRoute.
The recent control-plane fix correctly suppresses fabricated preview URLs.

Implementation prompt: update the readiness gate to wait for ready/running,
assert that this route-less fixture has no preview URL, and retain rollout
and running-pod verification. Update the release workflow contract check.
Do not restore synthetic URLs to satisfy this test. Public HTTP routing needs
a separate fixture with a real route and HTTP reachability assertion.

The before-materialization ImagePullBackOff and foreign Secret conflict in
the supplied log are expected negative checks; subsequent materializations
and Helm commands succeeded.
