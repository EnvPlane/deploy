# Saved FinOps configuration only reaches the init container

Status: fixed locally; runtime-targeted render regression added; no push.

Live generation 5 had a valid `agent.finops` Helm map but the actual Agent
container only had the node-inventory flag. The complete HTTPS/CA/origin and
storage/network environment variables were rendered on the connectivity init
container, which does not collect metrics.

Implementation prompt: render the profile on the actual Agent runtime, retain
the public CA read-only mount and explicit RBAC opt-in. Assert the container
name when testing, not a text match anywhere in the rendered Deployment. Do
not bypass TLS, broaden networking, or patch Pod environment out of band.
