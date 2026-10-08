# Installer admission profile needs explicit API-defaulted match constraints

Actual candidate restore discovered SSA conflict on `spec.matchConstraints` when
the reviewed installation profile followed projected source RBAC ownership.
API defaulting adds matchPolicy Equivalent, empty selectors and resource rule
scope `*`; leaving these implicit makes atomic match constraint ownership
different across field managers even when the intended matching is identical.

Renderer now states those exact existing defaults for both fail-closed admission
policies. No rule, principal, selector meaning or validation is weakened. Apply
through the owner of the reviewed policy; do not force unrelated ownership or
disable admission. Candidate replacement credential TLS/auth/full-profile dry
validation succeeded independently after RBAC rule updates.

## Codex implementation prompt

Keep profile round-trip/idempotence coverage across Kubernetes API defaults and
SSA field managers. Verify deny controls after source-to-candidate migration,
including foreign ClusterRoleBinding creation rejection. Continue source backup
and target-only data restoration; preserve source/rollback and no-push boundary.
