# Prepared MySQL rescan / product PVC-copy attempt on 0.4.715

Result: BLOCKED before authenticated scan dispatch; product backup/restore NOT RUN.

Normal Chrome UI selected test-app-base and Start resource scan. API twice
refused full executor reconciliation because saved clone selections lack
authenticated source UID. UI still shows old completed attempt 2, twelve
resources, old mysql-data and no fresh mysql-data-fresh-715. Historical completion
does not prove the new source was scanned. No copied data or target PVC was created.

Root cause is the discovery/Runner onboarding dependency cycle documented in
control-plane/issues/2026-10-11/pvc-copy-scan/discovery-blocked-by-unscanned-copy-profile.md.
Local source fix separates Agent-only discovery from full Runner reconciliation;
full source UID and authority checks remain strict. Targeted regression, broader
server tests and race checks recorded in the corresponding source iteration.
Existing candidate has not been updated with that source change.

One ordinary wizard navigation save also returned HTTP 502 through the known
local-domain relay; this is already tracked in the 715-route-regression ticket,
not interpreted as committed progress or scan success.

QA score for this narrow rescan path: 1/5 (prerequisite recovery action cannot
complete; safe refusal prevents unverified copy, but guidance leads into a cycle).
Screenshot: /private/tmp/envplane-715-pvc-copy-scan-blocked.jpg.

Do not insert scan tasks/UIDs directly into storage, weaken copy gates or replace
copy with empty volumes to claim acceptance. After aligned candidate deployment,
repeat fresh discovery, new PVC source reference review and independent approval,
fresh CNI evidence, then the actual Runner native backup/restore. Native restore
requires a nonempty supported database; verify an appropriate disposable test
dataset before invoking it. Prepared credentials and TLS remain available.
