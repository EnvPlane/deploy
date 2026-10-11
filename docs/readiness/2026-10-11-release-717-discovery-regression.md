# Candidate 0.4.717 / prepared MySQL discovery

## Upgrade

- Active kind context kind-envplane-readiness-682, envplane release revision 15.
- OCI archive digest sha256:ca773f941c5a0ff3df7e87fa2f952b7b4bea2e8934559ab86656d12f373e7081.
- Packaged control-plane source beca3d52de1a332f49be340d3c0e9d96d12855b5;
  image digest sha256:468bb972d9b75600afddf9f5b241253fa7c3135b6cf786fd77e91fbc64466768.
- Complete prior values, manifest and PostgreSQL custom dump retained privately
  under /private/tmp/envplane-717-verification.xer3xys6. pg_restore --list succeeded;
  only its temporary Pod copy was removed. This is archive validation, not DR restore.
- Upgrade wrapper used reset-values and complete prior operator values.
- Core API/frontend/PostgreSQL/Redis Ready, zero restarts observed; browser
  authenticated session still works.

## Live regression PASS

- Normal Bootstrap Start resource scan accepted attempt 3:
  scan-6c3e8ee1da3b3ae8b73569817a9912c9.
- Refresh scan status completed, seventeen resources, including mysql-data-fresh-715.
- Agent-only reconciliation rolled out the project Agent; project Runner remained
  unchanged. The stale-profile discovery dependency cycle is closed live.
- Root/application login, verified source TLS, exact backup grants/lock,
  plaintext and hostname negative tests still pass after umbrella upgrade.
- Saved new MySQL source references in normal UI and read them back: pinned actual
  running MySQL image digest, mysql Service, separate backup Secret username/password
  keys, public CA Secret ca.crt and mysql.test-app-base.svc. No credential values
  were transferred to the browser.
- QA score 4/5 for discovery recovery: scan works; the known local-domain relay
  still returned one wizard-navigation HTTP 502. Explicit Next retry succeeded.
- Screenshot /private/tmp/envplane-717-source-references.jpg.

## Backup/restore NOT RUN

New app database has zero base tables. Native copy refuses an empty database;
a disposable supported InnoDB/primary-key dataset is needed to verify transfer.
The current source-access approval also includes old retained mysql-data and
backend-data filesystem sources. Do not approve those merely to test the new
MySQL: first review intended resource selection and regenerate the exact profile.
Source authority requires a separate normal approval; no approval was submitted.
Copy choices were not replaced by mock/empty storage. Fresh CNI proof and source
classification/permissions remain gates before real provisioning.

The old MySQL PVC and data, backend-data and existing applications were not
deleted, copied, relabelled offline or modified by these checks. Full PVC-copy
acceptance remains open; a saved source reference is not restored-data evidence.
