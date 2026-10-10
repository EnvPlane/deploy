# SQL-only Runner lost its authenticated caller binding

ENVPLANE_PVC_COPY_RUNNER_SERVICE_ACCOUNT was emitted only for pvcCopy.enabled.
SQL-only profiles disable filesystem copying, but the SQL runtime also requires
that exact Downward API principal; legitimate reviewed profiles stayed unavailable.

Fixed: emit the shared spec.serviceAccountName field once when FS OR SQL is
enabled. Keep SQL fences, pinned images, root-init opt-in and production refs
receipt-derived. Add standalone SQL-only and mixed render regressions and check
vendored child parity. No SA/RBAC grants or source writes are added by this fix.
