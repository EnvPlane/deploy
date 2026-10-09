# Zero-values installation has no isolated ledger runtime role

Priority: P1 for advertised infrastructure-report/storage-evidence functionality. Status: OPEN; no runtime fix applied.

Candidate: signed umbrella 0.4.682, OCI digest sha256:46c97ee822e19e57f13315da754b3eaca5b863d2a4faf826d7d4f3bd3d7e4beb. Fresh cluster kind-envplane-readiness-682, Kubernetes v1.37.0 ARM64; installed with no values and no imported Secrets.

Observed: all six Pods become Ready, but bundled PostgreSQL role envplane has rolsuper=true and rolbypassrls=true. API deployment has no ENVPLANE_FINOPS_POSTGRES_DSN reference. Table tenant_infrastructure_cost_reports has RLS and FORCE RLS enabled. The selected API defaults finopsDB to the management DB; infrastructureRoleSafe rejects superuser/BYPASSRLS. Existing installation required an independently supplied metering connection. No authenticated report HTTP request was made in this fresh installation yet: OAuth setup is pending, so record this as a verified configuration/guard incompatibility, not a newly observed UI 503.

Implementation prompt for Codex: add an idempotent, credential-safe least-privilege ledger provisioning path for bundled PostgreSQL during installation, after application migrations have created required tables. Separate migration/owner credentials from runtime ledger credentials. Generate and retain credentials in Secrets, never plaintext values/logs. Grant only required table/schema privileges, preserve tenant-scoped transactions and FORCE RLS, never weaken infrastructureRoleSafe or storage-evidence authorization. Wire the ledger DSN to the API through Secret references. Specify external-PostgreSQL operator prerequisites and a safe approved reconciliation for existing installations. Cover concurrent starts, restart/upgrade, credential persistence, grants for newly added tables, and unavailable/partial provisioning with actionable diagnostics.

Acceptance: zero-values fresh installation serves an authenticated empty report without SQL patches, rejects cross-tenant reads/writes with populated fixtures, and uses a non-owner/non-superuser/non-BYPASSRLS ledger role. Rerun storage-evidence reads and price/budget scenarios on the new release. External operator-managed roles are not silently broadened. Preserve working installation data and credentials.

Evidence: /private/tmp/envplane-readiness-682.t5bJs0; see the production readiness report for commands and outcome boundaries.
