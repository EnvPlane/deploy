# Readiness continuation: billing, fallback and FinOps on 0.4.711

Date: 2026-10-11, Europe/Berlin. Explicit private kubeconfig/context:
kind-envplane-readiness-682. Helm envplane revision 12, umbrella 0.4.711.
Browser: existing authenticated Chrome owner session, tenant default/test-app.

| Plan gate / scenario | Result | Fresh evidence / boundary |
| --- | --- | --- |
| Installation health | PASS | Four core Pods Ready/Running, zero restarts; local root HTTP 200. |
| 12 / Free plan review and cancel | PASS scoped | Review change for selected Community opened Keep free modal; hosted checkout disabled. Cancel and reload preserved free active subscription v1.0.0 and quotas 1/2/1. No provider session, portal, payment or plan command performed. |
| 11 / configuration fallback preview | FAIL first attempt; PASS retry | Identical read-only TTL 24h intent first returned HTTP 502, retry produced valid deterministic ai_disabled_or_not_entitled proposal with quota/policy allowed. Reload showed default TTL 48h and zero active environments. Real provider/timeout/quota acceptance NOT RUN. |
| 10 / blank monthly budget rejection | PASS scoped | Save with blank form rejected: Budget currency must match the tenant FinOps currency. Reload monthly budget and full page confirmed no budget created. This tests invalid-form rejection, not monetary enforcement. |
| 10 / missing coverage rendering | PASS scoped | Telemetry refresh and page reload preserve no measured source windows, all rates UNKNOWN, report revision 0, infrastructure forecast UNKNOWN. No rates, report, currency or enforcement saved. Legacy headline estimated EUR 0.00 remains explicitly disclaimed below; not authoritative spend. |
| 9 / CNI freshness | PARTIAL | Readiness refresh at 09:12 UTC still verified authenticated single-node IPv4 TCP report checked 09:03:01 UTC. Under 15-minute TTL; expiry rejection NOT RUN in this iteration. No new probe, no old JSON replay. |

Community catalog advertises three feature slots, but the effective legacy free
subscription v1.0.0 grants two. Do not infer catalog migration or change grants
to make this acceptance pass. Paid licensing/payment recovery is not accepted.

New OPEN defect:
frontend/issues/2026-10-11/readiness-continuation/configuration-preview-transient-502.md.
The gateway cause remains unisolated; healthy Pods/root do not prove the POST
proxy path is healthy. Private screenshot of successful retry:
/private/tmp/envplane-711-preview-fallback-retry.jpg (not committed).

## Next blockers and boundary

Full feature lifecycle/copy remains BLOCKED by reviewed MySQL backup/admin/TLS
source preparation and filesystem source consistency/protection. No source
password reset, SQL privilege change, restart, original PVC write or RBAC
expansion performed. Real GitLab-originated MR delivery remains NOT RUN; the
previous signed self-probe is not that evidence. Remote onboarding, cross-tenant
live roles, actual AI provider responses, complete measured FinOps, sandbox
recovery, secure erase and DR/load/soak acceptance remain separate pending gates.

Browser Use/QA guided bounded read-only previews and reload checks; documentation
keeps observed failures, successful retries and unrun acceptance explicitly apart.
No production-ready conclusion or push is implied by this continuation.
