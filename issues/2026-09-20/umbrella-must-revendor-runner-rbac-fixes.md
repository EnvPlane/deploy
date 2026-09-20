# Umbrella must revendor Runner RBAC fixes

## Evidence

The `envplane-runner` source chart contained the project-scoped preview
namespace delete permission, but both the runner chart and the umbrella
dependency were still version `0.4.6`. The published umbrella `0.4.330`
therefore installed the previous vendored dependency: its Runner ClusterRole
had only `get`, and a UI delete failed with Kubernetes `Forbidden`.

## Required implementation

Bump the runner chart dependency version and regenerate the umbrella lock and
vendored archive whenever a Runner chart change affects rendered resources.

## Acceptance criteria

- The packaged umbrella contains the updated Runner RBAC template.
- A project-scoped Runner receives `get,delete` only for its generated preview
  namespace.
- An E2E UI create followed by delete terminates the environment and removes
  its namespace without an imperative RBAC patch.
