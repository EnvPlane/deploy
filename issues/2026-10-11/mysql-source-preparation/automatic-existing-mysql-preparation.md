# Automatic preparation of an existing MySQL source

Priority: P1 zero-setup acceptance. Status: PARTIAL: administrative preparer and
fresh-base chart support implemented; application UI/controller/live acceptance
blocked. See ui-controller-approval-and-tls-renewal.md.

Local evidence: 14 unit/mocked operation cases, disposable networkless MySQL 8.0
TLS/grant/lock/data-preservation acceptance, 6 chart render cases and chart lint.
Read-only current-source preview refused missing MYSQL_ROOT_PASSWORD Secret
reference. The existing source uses an unretained random root password; no SQL,
source restart, permission expansion or credential recovery was attempted.

## Observed gap

On release 0.4.711 the reviewed PVC-copy onboarding requires a dedicated
backup account and verified TLS references but cannot prepare either. The
test-app source remains blocked before copy. Existing source-profile approval
must not be misrepresented as authorization to change SQL accounts, TLS or
restart the source database.

## Implementation prompt

Build a separately reviewed administrative preparation operation, bound to
the exact cluster/PVC/Service/StatefulSet identities and configuration. Generate
a distinct non-root backup credential and server TLS materials; do not change
application credentials or mount/write the source PVC from a helper. Use
bounded SQL inputs, a local authenticated administrator session, strict
server-name TLS verification and minimal direct catalog/backup grants. Refuse
unknown layouts, existing conflicting objects/accounts and concurrent drift.
Store credentials only in dedicated protected Secrets, never in previews,
compiled configuration, logs or browser responses. Keep failure/retry state
recoverable without blind password rotation or deleting source data. Require
explicit approval for a source restart and report failed verification honestly.
Integrate the administrative plan with tenant-scoped independent approval/UI
and desired-state ownership; ordinary copy workers must not gain this authority.

## Acceptance gates

- Read-only preview; exact digest confirmation before writes.
- TLS and SQL preparation on supported existing MySQL 8, with verification.
- UID/configuration drift, injection, collisions and credential leakage refused.
- Retry retains owned credentials and cannot adopt another account.
- No source PVC/data deletion or application-password changes.
- Normal UI approval and controller lease integration, management and remote.
- Live deployed copy through the product; not just an operator fixture.
