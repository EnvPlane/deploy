# Release 0.4.711 readiness follow-up

Date: 2026-10-11, Europe/Berlin. Candidate unchanged: kind
`envplane-readiness-682`, namespace `envplane`, Helm revision 12.
This is a scoped follow-up to the root PRODUCTION_READINESS_PLAN.md,
not complete production acceptance.

| Plan gate / scenario | Result | Evidence and boundary |
| --- | --- | --- |
| Installation health | PASS live | Helm deployed 0.4.711; API/frontend/PostgreSQL/Redis 1/1, no restarts; domain HTTP 200 |
| API/schema compatibility | PASS live | /api/v1/openapi.json SHA-256 d726e2c238e6085a5ff9a4f7eb093ab68e90f21ac3a92e09e3e7e5941d94ee86 matches canonical contracts |
| Anonymous reads | PASS live | GET /api/projects, /api/environments, /api/projects/test-app/cost-policy each returned 401; no credentials supplied |
| Authorization/quotas | PASS local | Uncached race HTTP tests: tenant-scoped mutation allowlists, static token default-tenant route allowlist, clean-install write-token scope, Free-plan create quota/cleanup bypass |
| Existing authenticated UI | PASS live smoke | Chrome owner/default session; Projects, test-app Overview/Bootstrap, Jobs, GitOps and Cost load |
| PVC intent preservation | PASS live smoke | Both selected source PVCs still Copy source data (unavailable); no empty-volume substitution; source-profile review pending |
| Base workload/storage | PASS live health | test-app-base backend/frontend/MySQL 1/1, no restarts; original backend-data and mysql-data Bound to unchanged PV names |
| Flux health | PASS live health | source, kustomize, helm and notification controllers each 1/1; not proof of webhook delivery |
| FinOps missing coverage | PASS live smoke | No pricing versions, source windows or reconciled report; explicitly UNKNOWN. Legacy fixed metadata estimates are labeled non-authoritative |
| Fresh lifecycle / deployed copy | BLOCKED | Bootstrap not compiled, source access unreviewed, SCM not verified, CNI evidence unverified/stale |
| Remote onboarding | BLOCKED | No target-Pod-reachable HTTPS management endpoint profile and no remote cluster configured in this installation |

Targeted local command, in control-plane:

```sh
GOWORK=off ENVPLANE_RUN_HTTP_TESTS=1 go test -race -count=1 ./internal/server \
  -run 'Test(TenantScoped.*Allowlist|StaticTokenDefaultTenantRouteAllowlist|FreePlanCreateQuotaResponsesAndCleanupBypass|StaticAPIWriteTokenUsesDefaultTenantOnlyForCleanInstallRoutes)$'
```

The first sandboxed attempt could not access the normal Go build cache; the
authorized rerun passed. This was a tooling boundary, not a product test failure.
Anonymous denial does not certify live cross-tenant isolation or all user roles.
Jobs is empty in the selected test-app scope, not a global queue/recovery proof.
GitOps displays the configured repository, not successful SCM delivery.

## Next steps and existing tickets

1. Review dedicated MySQL backup-account rights, verified TLS references and
   source protection before saving source policy. Do not grant SQL rights or
   weaken isolation implicitly. Filesystem copying also needs its approved
   source-consistency path; a MySQL profile alone does not certify backend-data.
2. Complete Bootstrap review and obtain actual SCM delivery and fresh
   authenticated CNI enforcement evidence; retain copy selections.
3. Execute management lifecycle and copy proof, then repeat against a remote
   target after its HTTPS profile and onboarding are ready.

Existing copy acceptance tracking:
control-plane/issues/2026-10-10/production-readiness/bootstrap-pvc-clone-does-not-copy-data.md.
Existing independent domain-routing tracking:
issues/2026-10-10/local-access/kind-domain-route-still-depends-on-retired-minikube.md.

Scoped UI smoke usability: 4/5. Readiness explains the blockers and maintains
copy intent, but completion still requires platform prerequisites. No new product
defect was confirmed in these scenarios. No configuration was saved, source data
changed, permissions expanded, feature environment created, payments initiated
or commits pushed. AI/provider, secure erase, full DR and load/soak remain NOT RUN
in this follow-up. Overall decision remains LIMITED PILOT / acceptance pending.
