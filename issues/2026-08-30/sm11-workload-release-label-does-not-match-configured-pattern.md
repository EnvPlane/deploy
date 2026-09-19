# SM-11 workload release label does not match configured pattern

## Problem

The private-registry clean-install gate configured the Helm release name as
`{{ .project.id }}-{{ .environment.name }}`, but later searched workloads with
the unrelated `default-<environment>` release label. A correctly created and
Running workload was therefore reported as absent.

## Impact

The mandatory clean-install release gate fails after the environment reaches
Ready, masking successful first-environment provisioning.

## Resolution

Derive the expected Helm instance label from the same project and environment
identifiers passed to the signed Bootstrap deployment configuration.
