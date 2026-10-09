# Chart source, lock, and vendored package alignment

Status: implemented locally; hosted CI pending.

Agent source version 0.2.39 diverged from umbrella dependency/package 0.2.36, blocking CI and runtime update proposals. Node inventory was configured differently in the preflight and runtime containers. The control-plane chart payload also differed from the committed package.

Fix: use the RBAC node inventory opt-in for both containers, bump Agent to 0.2.40 and control-plane to 0.3.61, update umbrella dependencies and Agent bootstrap contract, and regenerate lock/vendor archives. Published chart versions must never be overwritten.

Validation: vendored drift guard, all Go Helm chart tests, and drift regression test passed.

Implementation prompt: keep canonical source, dependency versions, lockfiles, archive payloads and runtime bootstrap defaults aligned; publish new immutable versions and verify full release compatibility before upgrading.

