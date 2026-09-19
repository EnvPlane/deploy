# Agent workload status collector lacks Pod RBAC

## Observed

Feature environment Deployments and Ingress were healthy, but the Agent
reported the environment as `failed`.

## Root cause

The Agent's workload collector lists Pods to determine readiness. The
read-only discovery Role/ClusterRole omitted core `pods`, so collection failed
and the watcher converted the environment status to `failed`.

## Fix

Add core `pods` with only `get`, `list` and `watch` to the Agent discovery
rules and publish a new child-chart version.

## Verification

With healthy Deployments, Pods and Ingress, the Agent reports the feature
environment as `ready` and no longer records a collector failure.
