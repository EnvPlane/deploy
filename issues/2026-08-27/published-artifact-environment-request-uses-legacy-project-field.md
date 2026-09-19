# Published artifact environment request uses a legacy project field

## Problem

The default published-artifact E2E payload sends `project_id`, which is not a
field in the versioned `CreateEnvironmentRequest` contract. The API therefore
falls back to the default project instead of using `ENVPLANE_E2E_PROJECT_ID`.

## Required behavior

Use the canonical `project` field in the default environment payload while
preserving explicit caller-provided payload overrides.

