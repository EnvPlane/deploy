# SM-09 environment request uses unsupported project fields

## Problem

The private-registry lifecycle harness sends `project_id` and `cluster_id` to
`POST /api/v1/environments`. The versioned `CreateEnvironmentRequest` contract
uses `project` and `clusterId`. Unknown JSON fields are ignored, so the API
falls back to project `default` and returns `project not found` instead of
creating the fixture environment.

## Required behavior

- Send the canonical versioned environment request fields.
- Keep a static release-contract assertion for both project and cluster
  bindings so this cannot regress silently.

