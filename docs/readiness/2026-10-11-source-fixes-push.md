# Source fixes and grouped publication after 0.4.711 checks

Date: 2026-10-11. Installed acceptance remains umbrella 0.4.711 revision13.
These source changes are not claimed deployed in that release.

## Implemented

- control-plane f80600c: ordinary Bootstrap progress/namespace metadata saves
  queue executor convergence rather than returning a later source/Helm failure
  as a failed save. Existing durable runtime state records success/failure with
  sanitized source-identity guidance. HTTP save/readback failure-injection test
  proves committed step survives the blocked worker and later failure. Scan and
  explicit Compile keep their own strict runtime prerequisites.
- frontend ac2c92a and follow-up: one independent SCM panel appears after
  validated GitLab/Flux repository setup without final resource Review. Changed
  repository validation resets webhook readiness; offline/other providers do
  not trigger GitLab actions. Tests exercise no progress writes and one panel.
- Gateway preview errors explain no configuration application and explicit
  manual retry; interaction test proves no automatic POST replay and recovery.
  This improves the error path, NOT the unidentified transport root cause.
- Earlier unpublished deploy administrative MySQL preparer and test-app base
  chart admin/TLS support are included in grouped push after repeat validation.
  No lost password reset or source-data mutation occurred.

## Local checks

- Full control-plane go test ./... PASS; Bootstrap/same-cluster race suite PASS;
  go vet internal/server and control-plane brand diff gate PASS.
- Frontend 508 unit tests PASS, typecheck and lint PASS. An initial new test
  hung while serializing a DOM assertion; corrected to a boolean assertion,
  then the full suite passed. No cancelled test is counted as acceptance.
- MySQL administrative preparer: 14 unit cases PASS; disposable networkless
  official MySQL TLS/backup-grants/source-preservation acceptance PASS and
  owned container cleanup completed. No running cluster DB used for this test.
- test-app chart: six render regressions PASS and helm lint PASS.
- deploy remote stable-doc commit merged without force/reset before publication.

## Remaining, not closed by publication

1. configuration-preview-transient-502: transport origin remains unknown;
   no ECONNRESET/ECONNREFUSED/ETIMEDOUT in inspected frontend logs. PARTIAL.
2. Normal product UI/controller approval and TLS renewal for existing MySQL
   remains OPEN. Operator-only preparer is not full zero-setup implementation.
3. Current base MySQL admin credential is unavailable; legitimate DBA recovery
   and reviewed source filesystem consistency remain live lifecycle blockers.
4. Deployed UI/runtime regression requires newly built images and a candidate
   umbrella; neither git push nor local unit tests prove hosted CI or deployment.

Debug/code-review skills guided separation of committed metadata and runtime
failure, retention of permission gates and safe error handling. Documentation
records local/deployed boundaries. Existing untracked caches and _to_delete
directories were neither staged nor removed. No license code, token, private
key or complete operator values are committed.
