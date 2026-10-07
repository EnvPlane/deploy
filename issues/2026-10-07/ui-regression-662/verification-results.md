# Published umbrella 0.4.662 verification

## Deployment

- Upgraded envplane/envplane on context envplane from revision 31 (0.4.652) to revision 32 (0.4.662).
- Used scripts/upgrade-umbrella.sh with local-platform/envplane-zero-setup-license-values.yaml and reset-values; did not retain old image overrides.
- OCI digest: sha256:ac7005155f32143379627e3d29465c768e2583e56d59530b55845bc8cffb168b.
- API and frontend deployments ready, one replica each. PostgreSQL and Redis ready.
- Rollback reference: Helm revision 31. No rollback needed during this pass.

## Live Chrome UI observations

- Existing authenticated session retained; first-run remains complete.
- EUR and app policy TTL 24, active limit 3, memory 0 preserved across reload.
- Negative memory rejected by native min validation; fractional FinOps TTL rejected by integer step validation. Focus goes to invalid field.
- Create environment rejects fractional TTL with explicit whole-number error. No test environment was created.
- Cancel restores focus to Create environment opener.
- Qualified remote readiness wording and Flux access advisory visible in Project Overview and Create dialog.
- Three pre-existing Terminated records retained; no cleanup or purge executed.
- Enterprise activation active; enabled AI features and configured Anthropic credential/policy retained. No provider request or credential replacement performed.
- Management HTTPS profile loaded from API; bethunder-local healthy and project-selectable.

## Limits and follow-up

- This is a bounded upgrade/UI regression pass, not a full live lifecycle or all-agent evaluation.
- Optional broad Flux installer status access was not granted; future names may still need approved migration.
- Preview DNS/HTTP route was not retested.
- A management-cluster project Runner was already unavailable before upgrade and remains CrashLoopBackOff; see adjacent ticket.
- Browser QA score for tested paths: 4/5. Validation/readiness behavior passed; outstanding runtime issue prevents claiming all execution targets healthy.
- Evidence screenshot: /private/tmp/envplane-662-remote-cluster.png.
