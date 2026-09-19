# Management Agent cannot collect feature environment events

## Observed

The umbrella-installed management Agent received `403 Forbidden` while listing
core Kubernetes `events` in a feature namespace. Status and Flux reports could
complete, but diagnostics were incomplete and the environment was marked
failed.

## Root cause

The Agent event collector calls the core Events API, but the chart's
read-only discovery Role/ClusterRole omitted `events`.

## Fix

Add core `events` with only `get`, `list` and `watch` to the existing
read-only discovery rules. No write verbs or new RBAC scope are introduced.

## Verification

Render the Agent chart contract and verify an installed management Agent can
list events in a feature namespace without a `403`.
