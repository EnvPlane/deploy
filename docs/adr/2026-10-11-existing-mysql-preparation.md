# ADR: separate administrative MySQL preparation from copy execution

Status: Accepted for the operator preparer; application approval/controller
integration remains pending. Date: 2026-10-11.

## Context

Existing source-profile reconciliation installs approved source fences and copy
permissions. It deliberately neither holds SQL administrator credentials nor
changes source workloads. An existing MySQL source needs a distinct catalog /
backup account and server-name-verified TLS before its normal copy path works.
The current test-app source uses an unretained random root password, so that
administrative authority is unavailable. This is not permission to bypass SQL
authentication, scrape logs or reset source credentials automatically.

## Decision

Use a separate, explicit administrator operation with a metadata-only preview,
cluster/source UID and configuration binding, exact digest confirmation and
restart acknowledgement. Keep the ordinary copy Runner's source authority
unchanged. The first preparer supports a one-replica official MySQL 8
StatefulSet and existing root password Secret reference. It generates an
independent backup credential and source-only TLS materials, verifies exact
direct grants/TLS/backup-lock access and emits metadata references only.

The preparer retains immutable owned Secrets across failures/retries. It does
not adopt another account, rotate application/root passwords, delete storage,
disable grants/TLS verification or silently roll back a source. Missing
administrator credentials, unknown layouts and ownership conflicts fail closed.
Explicit desired-state ownership review is required for Helm sources; the
test-app chart now accepts the TLS Secret reference. The operator must persist
that reference before subsequent Helm/GitOps reconciliation.

## Alternatives

- Give the copy worker source root/SQL mutation rights: rejected; expands
  routine copy authority and weakens the source boundary.
- Use init-file/skip-grant-tables or mine logs to recover unknown root access:
  rejected as an automatic preparation path; requires an independent credential
  recovery/downtime decision and may leak credentials.
- Require hand-written GRANT and certificate commands: replaced by the reviewed
  preparer, but possession of real administrator authority remains a prerequisite.

## Consequences and remaining gates

Unit/mocked Kubernetes operation tests and a disposable networkless MySQL engine
prove only this administrative tool. They do not close application UI approval,
normal controller leasing, remote onboarding, source GitOps persistence,
certificate rotation or deployed copy acceptance. A backend/contract/UI bridge
must independently review this stronger authority and must never turn existing
PVC-source approval into automatic SQL/workload mutation consent.

MySQL grant rationale: [privilege reference](https://dev.mysql.com/doc/refman/8.0/en/privileges-provided.html)
and [mysqldump reference](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html).
