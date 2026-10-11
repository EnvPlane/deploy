# Test MySQL recreation on candidate 0.4.715

Scope: kind-envplane-readiness-682, namespace test-app-base, release test-app-base.
User approved recreating only the test MySQL with retained, known credentials.

## Completed

- Chart 0.1.5 supports an explicit MySQL claim name and opt-in Helm retention.
- First upgrade recorded retention of mysql-data in the release manifest.
- Backend writers and MySQL were scaled to zero before switching storage.
- Created immutable administrator Secret mysql-admin-fresh-715 with a generated
  password. No password was printed or committed. Explicit Secret reference is
  used because the base deployment contains environmentId; the feature guard
  against baseline administrator generation remains unchanged.
- Release upgraded with complete saved values and reset-values, not reuse-values.
- Fresh claim mysql-data-fresh-715 is Bound to
  pvc-e9544aef-eecb-4b64-a274-19f25dddf4fd.
- Original mysql-data UID and binding remain unchanged; original PV is
  pvc-b039d9d6-52c3-401e-89ce-cd943bcd7f6a. No original data was deleted.
- mysql-0, backend and frontend Ready. SQL root login and application-user login
  to app database verified. Existing application password unchanged.
- backend-data remains on its original PV.
- Seven chart render tests and helm lint passed.

Protected values, original manifest/PVC and metadata-only summary are under
`/var/folders/k3/jv59z3zn7jl6r06wvz_6jmvh0000gn/T/envplane-mysql-recreate-715.nnwfbws1`.

## Rollback boundary

Stop backend writers and MySQL before switching back. Restore the previous full
values from values-before.json (random-root environment, original mysql-data),
using a reviewed chart and reset-values. Never attach original data with the new
root Secret and claim password recovery: environment variables do not reset an
initialized database. Retain the fresh PVC and Secret until rollback is reviewed.
No destructive cleanup of either datadir has been authorized or performed.

## Remaining

Prepare verified TLS and a dedicated minimum-grant backup user using the existing
administrator-only source preparation workflow. Persist TLS reference in desired
state, rescan the new PVC identity, review source profile/permissions, then perform
actual logical backup/restore and isolated credentials/data checks. This operation
is not evidence of successful PVC-copy or recovery of the old root password.
