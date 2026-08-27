# SM-09 harness omits quota tenant context

## Problem

The private-registry harness authenticated with the chart-issued API token but
did not select a tenant. Environment creation is quota-controlled and rejects
mutations without an explicit tenant context.

## Resolution

Send the default tenant through `x-envplane-tenant` on every authenticated
harness request, with an override for a dedicated SM-09 tenant.
