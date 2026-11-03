# Issuer chart regression tests require locked dependencies on clean checkout

Status: fixed in PR #1159.

Evidence: Deploy CI run 41667734507, job 126027488125 failed at issuer profile
tests before rendering: Chart.yaml declares envplane-frontend, but the ignored
standalone charts archive is absent in a fresh clone. Local warm-cache runs passed.

Fix: suite initialization builds the locked local file:// dependency with
`helm dependency build --skip-refresh`. Missing dependencies fail setup rather than
being confused with an expected profile validation error. No tests are skipped.

Codex verification prompt:

Run the issuer profile suite from a fresh tracked-files checkout without ignored
chart caches. Verify all 13 tests pass and committed vendored umbrella drift stays
clean. Require successful hosted Deploy CI on the final PR SHA before merging.
