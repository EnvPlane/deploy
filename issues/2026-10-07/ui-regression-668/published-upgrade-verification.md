# Published 0.4.668 upgrade and UI regression verification

## Deployment

Approved upgrade completed with the standard upgrade-umbrella wrapper and existing durable operator values. Helm namespace/release envplane, context envplane, revision 34, deployed 2026-10-07 20:05 Europe/Berlin. Umbrella digest sha256:fc1c5168297cccc83acb04b37035a32301f4daeec334d94c5c75593f3082cee2.

Frontend now uses published sha256:fa4e05b746fd4e3ea2f57d6639f8835d6733e7a177369c7a76e4bc5e729c45df, source 1c70837. API remains published f8b22f3 digest 8c3395f9e0fe143e9bf3720a2fb2f700bc4ebbb26a52631cb02d38909ad10045. Both ready 1/1. Local frontend image override removed by chart defaults. Project Agent/Runner remain Running 1/1, zero restarts; retired singleton workloads remain scaled to zero.

## Live Chrome results

- Activation active; first-run complete, dashboard link visible and functional.
- Bootstrap retired Runner panel not visible, computed display none, height 0. Managed Runner visible/online.
- Unchanged project Settings saves with empty optional legacy preview default. TTL stays 24h, compiled preview config v6 retained.
- Refresh readiness reports the already-known fresh webhook verification prerequisite; no webhook registration/rotation/public exposure performed.
- Existing e2e-ui-full-652-1007652 remains Ready, Full, TTL 24h. No cleanup, Recreate or new resources initiated.
- Download support bundle creates a new JSON file in the normal Chrome Downloads directory. v1 bounded metadata verified without credential output. Host download event timed out but actual artifact confirms receipt; this is not an export failure.

Evidence: /private/tmp/envplane-668-first-run-complete.png, /private/tmp/envplane-668-managed-runner-review.png, /Users/alex/Downloads/envplane-first-run-support (2).json.

QA score for tested release regressions: 5/5. This does not certify all UI/lifecycle paths. External preview DNS and fresh SCM delivery verification remain open; injected download failure/retry is locally mock-tested, not artificially induced in the live user browser. No full-suite rerun in this upgrade pass; prior commit tests were 219 unit and 80 mock passed, 6 optional skipped.

Rollback reference: previous Helm revision 33 / umbrella 0.4.665. No rollback performed.
