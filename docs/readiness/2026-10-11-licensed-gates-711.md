# Licensed readiness gates on umbrella 0.4.711

Date: 2026-10-11, Europe/Berlin. Target kind-envplane-readiness-682,
tenant default, project test-app; Helm envplane revision 13.
Active local-test-full test activation, not production or paid-provider proof.

| Plan scenario | Result | Observed evidence and limits |
| --- | --- | --- |
| 3/6: licensed environment admission | PASS negative only | Create environment remains disabled; test-app requires compiled Bootstrap and fresh authenticated NetworkPolicy evidence. Refresh did not bypass either requirement. No environment created. |
| 9: CNI evidence expiry | PASS scoped | Earlier 09:03:01 UTC authenticated probe no longer passes readiness after its 15-minute freshness window. Project and Environments show unverified/stale and explicit creation blocker. No forged timestamp/report replay or new diagnostic run. |
| 11: invalid TTL preview | PASS | Intent requesting 99999 hours rejected with ttlHours must be between 1 and 720. Read-only request; no save/apply control used. |
| 11: fallback recovery after invalid preview | PASS scoped | New 24h TTL intent produced valid configuration_proposal, full mode, deterministic ai_disabled_or_not_entitled fallback, quota/policy allowed. No 502 in these two requests; intermittent ticket remains OPEN, not resolved by this sample. |
| 11: preview persistence boundary | PASS | Reload returned Overview, default TTL 48h, active environments 0. Provider remains disabled; activation does not enable external provider execution. |
| 7: public unsigned SCM request | PASS negative | POST to configured public GitLab receiver with minimal merge_request object and no signature returned HTTP 401. No real GitLab event/delivery acceptance inferred. |
| 7: wrong-token SCM request | PASS negative | Local receiver POST with explicitly invalid non-secret token returned HTTP 401. UI Jobs shows no jobs in selected test-app scope. |
| 4: anonymous reads after activation | PASS scoped | Local frontend API proxy returns HTTP 401 for activation status, activation identity, entitlements and test-app project routes without credentials. Does not prove cross-tenant roles or revocation. |
| 8: source preservation | PASS metadata only | backend/frontend/mysql Pods Ready, zero restarts. backend-data/mysql-data still Bound to original PVs pvc-0405be64-deee-41bf-82f0-6ef47c5f59a8 and pvc-b039d9d6-52c3-401e-89ce-cd943bcd7f6a. No source DB content mutation/credential recovery attempted. |

Private screenshot: /private/tmp/envplane-711-licensed-admission-blocked.jpg,
outside Git. UI flow QA 4/5 for explicit licensing, readonly fallback and
fail-closed prerequisites; end-to-end acceptance remains incomplete.
Browser Use/QA skills constrained actions to ordinary UI/read-only previews;
documentation separates negative acceptance from missing successful lifecycle.

## Remaining blocking prerequisites and next steps

Full create/Ready/Recreate/cleanup with requested PVC copy is BLOCKED. Existing
test-app-base/mysql lacks retained admin credential; source backup grants/TLS
must be prepared with legitimate DBA access, not recovered from logs or bypassed.
Filesystem PVC copy also needs reviewed source consistency/protection. Existing
operator preparation tools do not prove integrated clean onboarding. No source
restart, SQL grants, auth weakening or live RBAC expansion was performed here.
After approved source preparation: refresh scan/review, Compile; then rerun the
authenticated CNI probe before creation, because current stored evidence expired.

Real SCM MR delivery, new remote cluster onboarding, real AI provider matrix,
measured nonempty FinOps, sandbox billing recovery and disaster-recovery/soak
remain NOT RUN on this candidate. Current negative checks do not close those
production gates. No new defect was observed in this iteration. No push.
