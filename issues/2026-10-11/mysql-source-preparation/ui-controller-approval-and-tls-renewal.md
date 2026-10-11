# Bridge MySQL administrative preparation into approved onboarding

Priority: P1. Status: OPEN. Operator preparer implemented, not normal product UI.

Do not close this using operator/native fixture results. Existing source-profile
approval does not authorize root SQL operations or a source restart.

## Codex implementation prompt

Add a separately scoped tenant/project administrative preparation contract and
metadata-only UI preview/request flow. Bind inventory, source UID/config digest,
DB administrator credential reference, exact SQL grants, installer access,
source restart and desired-state owner to independently approved authority.
Execute through a durable idempotent controller lease without source root rights
in routine copy workers. Integrate actual Helm/GitOps ownership before source
rollout; reject unsupported operators/layouts. Publish contracts and align all
consumers. Reports must contain only references and bounded verified status.
Provide safe partial-SQL-grant recovery after authenticated credential ownership
proof, cancellation/readback and certificate expiry/renewal/CA rotation. Never
repair an unowned SQL account, bypass auth/TLS or fabricate copy completion.
After administrator credentials are available, test fresh management/remote
onboarding and live copy through the actual product path with data preservation.

Acceptance: no manual SQL/certificate construction; approval cannot be reused
across tenants, replacement UIDs, changed grants or restart policy; no namespace-
wide Secret or source exec rights silently added; desired state survives
reconciliation; expired certificates fail closed; normal copy authority unchanged.
