# Scoped live UI verification on release 0.4.652

Project app, disposable feature e2e-ui-full-652-1007652, MR 1007652.

Passed: create, executor retry after the approved exact get-only RBAC migration,
Recreate using recorded configuration v5, Flux readiness, three Ready services,
three Ready Pods, two Bound feature PVCs on envplane-local-path, Pin persisted
after reload, Unpin, Extend TTL persisted after reload, unchanged cost-policy
save, safe FinOps unknown-price explanation/proposals, and first-run completion.
License and Anthropic configuration were inspected without changing credentials.
This does not prove a provider invocation or a fresh zero-setup installation.

Approved UI Delete passed: Terminated; namespace and exact Flux object absent;
PV pvc-5aa408a9-46ed-4408-a744-a0b4524d2709 and
PV pvc-1579ebb2-9ba6-4390-a695-8c10f036c9d5 absent. Read-only node checks confirm
their recorded /opt/envplane-local-path backing paths and symlinks absent.
No forced finalizer, manual PV deletion or manual backing-path deletion used.
Test volume data was reclaimed; metadata history intentionally retained.
Base app-backend backend-data/mysql-data remain Bound to their original PVs;
base backend, frontend and MySQL Pods remain 1/1 Running.

Blocked: browser preview URL returns ERR_NAME_NOT_RESOLVED for the configured
preview.company.com domain. Workload readiness is not public-route proof.
The legacy exact-name installer profile still needs an administrator-approved
future-name delegation policy; this test did not broaden namespace permissions.
Known Diff contrast fix frontend c68c1f0 still requires a deployed-release retest.
No claim is made that all product functionality has passed.
