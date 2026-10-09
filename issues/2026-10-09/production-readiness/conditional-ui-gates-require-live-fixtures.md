# Six conditional UI gates are not covered by the mock pass

Status: OPEN coverage prerequisite, not a reproduced UI defect. Candidate campaign: umbrella 0.4.682.

Fresh frontend run: 85 passed, 6 skipped. The skipped scenarios are two release-gate flows (multi-namespace GitLab Flux immutable parity/no secrets; rejection of placeholder/stale artifacts) and four SCM webhook flows (unconfigured Compile block; reconcile/verify unlock; stale proof cannot unlock; status refresh cannot request one-time secret).

Verification prompt for Codex: provide the existing opt-in release/SCM fixtures on the isolated candidate after authenticated project onboarding. Run these six scenarios explicitly with the required fixture flags and capture results; use real delivery evidence where the scenario requires it. Preserve secret redaction, timestamp/parity gates and deny-by-default Compile behavior. Do not remove skip guards or report the mock suite as full real-cluster acceptance. Mock Stripe/AI fixtures and historical hosted release gates do not substitute for these current live scenarios.

Acceptance: each conditional scenario has a candidate-bound PASS/FAIL/BLOCKED record with its actual fixture type and sanitized artifacts. External GitLab writes/delivery tests stay within granted project scope; no production signing/token secrets enter screenshots or logs.
