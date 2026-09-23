# Publish Runner Pod-readiness RBAC in an immutable chart

## Observed

In isolated E2E with umbrella 0.4.380, `Refresh status` for a healthy Helm Direct environment failed with `pods is forbidden`: the project Runner service account could not list Pods in the feature namespace. The Kubernetes Deployment and Pod remained healthy. The installed Runner chart was `0.4.9`; its Helm manifest lacked the Pod read rule.

## Root cause

The canonical Runner chart gained namespace-scoped Pod `get/list/watch` in commit `369b2b7`, but its version remained `0.4.9`. The already-published immutable `0.4.9` artifact did not contain the rule, and the umbrella selected that old artifact.

## Codex implementation prompt

Publish the canonical Runner chart under a new immutable version and select it in the umbrella dependency. Regenerate `Chart.lock` and vendored chart artifacts. Run the Runner chart contract, umbrella render/dependency checks, then upgrade an isolated project Runner and verify `kubectl auth can-i list pods` for its service account in the exact feature namespace. Repeat `Refresh status` and ensure the healthy environment remains Ready. Do not grant Pod write verbs or cluster-wide Pod reads.

## Verification

- Runner and umbrella chart contract tests, Helm lint, and vendored-chart drift check pass locally.
- Upgraded only isolated project Runner `ep-runner-8cf93a7ffc80` to local chart `0.4.10` with existing values; Helm revision 7 is deployed.
- The Runner service account can list Pods in `envplane-e2e-pr-9002` but cannot list Pods in `default`.
- A new `Refresh status` completed successfully; `e2e-remote-smoke-local-375` returned to Ready and the old Forbidden error cleared.
- Published umbrella `0.4.388` contains Runner chart `0.4.10` and was deployed as isolated management release revision 23. The remote project Runner is on chart `0.4.10`; its service account can list Pods in `envplane-e2e-pr-9002` but cannot create Pods there. A fresh Runner status command succeeded, and the environment remained Ready after page reload.

## Status

Fixed and verified on published umbrella `0.4.388` in the isolated management/remote E2E clusters.
