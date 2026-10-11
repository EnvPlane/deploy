# MySQL copy dataset and retained-volume exclusion on 0.4.717

## Confirmed changes

The user approved creating control tables in the fresh test MySQL and excluding
the retained original volume from feature materialization.

- Target source: `kind-envplane-readiness-682`, `test-app-base/mysql`, database `app`.
- Fresh PVC: `mysql-data-fresh-715`, UID `e9544aef-eecb-4b64-a274-19f25dddf4fd`.
- The seed operation checked the expected PVC identity and an empty schema before writing.
- Two InnoDB tables with primary keys and an intra-schema foreign key were created:
  `ep_copy_accounts` and `ep_copy_events`, two rows each.
- Account balance sum: `12.3455`.
- Ordered event payload SHA-256:
  `ad9078b4089f9f2c1f7e0bc5432edad1b4338be65f9f7da9ee4ff98047b6d5a8`.
- Original `mysql-data` remained bound to
  `pvc-b039d9d6-52c3-401e-89ce-cd943bcd7f6a`; no original data was modified.
- Bootstrap Resource review saved its exclusion (`include=false`, `ignore`).
  Returning from the next step and refreshing the page preserved this selection.
- Verified TLS identity, backup grants/lock, root and app login, rejection of
  plaintext backup access and wrong TLS hostname all passed after seeding.

## Remaining blocker

The source-profile UI now reports `source review pending` after the inventory
change. Retry executor provisioning was submitted through the normal UI; a
subsequent profile refresh still did not expose a current approvable review.
An intermittent HTTP 502 also occurred during backward wizard navigation;
this is the already recorded local relay issue, not evidence of lost selections.

No source access approval, expanded RBAC, writer shutdown, feature creation or
product-native backup/restore was performed. Do not report this as copy acceptance.
`backend-data` still requires its separate filesystem-copy/fence workflow. The
fresh MySQL references remain saved; the source image, backup Secret keys and
public CA reference were read back through the UI without credential values.

## Next verification

Diagnose why normal reconciliation has not published a matching source review;
then inspect the exact new review, obtain the required access approval and fresh
authenticated CNI proof, and run native copy with independent target credentials.
Compare the two tables and checksum in the target and verify source isolation.

Local UI proof: `/private/tmp/envplane-717-retained-pvc-excluded.jpg`.
