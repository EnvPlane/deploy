# SM-09 fixture project lacks SCM provider for UI environment create

Same-cluster registration creates the chart-managed project from repository
IDs. The optional fixture reconciler normally enriches it with `git_repo`, but
it is intentionally not invoked during API startup. The live UI therefore
received a deploy-ready project without a SCM provider and correctly rejected
environment creation before issuing its POST.

The disposable SM-09 harness now uses its authenticated public API client to
persist the configured fixture GitHub repository reference before it compiles
the session and runs the browser lifecycle test.
