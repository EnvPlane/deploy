# PAY-012 native seller deployment handoff

Status: live blocked. New seller installations target Lambda/DynamoDB in
`eu-central-1`. The issuer's disabled `deploy/aws/serverless/` composition and
exact protected runtime artifacts are the deployment candidate. PostgreSQL
Helm, migration hooks and disposable SQL restore are historical standalone
compatibility evidence, not a prerequisite, import or cutover for this target.

The canonical review is in sibling control-plane:

- `docs/payment-production/runbook.md`: native recovery, operations and launch
  boundary.
- `docs/payment-production/sign-off.pending.json`: test/live native resource
  aliases and pending independent reviews.
- `scripts/check-payment-production-readiness.py`: offline blocked review check.
- `docs/payment-production/verification.md`: local, hosted and external evidence.

The issuer owns one DynamoDB financial authority plus required paired audit and
referenced versioned objects. Pin account, region, table incarnations, mode,
installation, signer, exact Lambda versions, role IAM and writer/producer epochs.
GF-012 supplies local paired recovery rehearsal. GF-012-F01 must admit restored
resource identities with GF-001 authority and GF-010 runtime. GF-010-010's hosted
restore failure remains open. GF-013 in provider acceptance stream 09 owns actual
AWS restore, IAM/custody and measured RPO/RTO, followed by test-provider proof.

Before any activation review, prove distinct test/live provider and secret
references, TLS public webhook/body preservation, private gateway/operator/
recovery/signer access, protected signer and version rollback, sole writer,
durable reconciliation and DLQ redrive, delivered alerts, reviewed retention and
confirmed seller/tax/support details. Preserve accepted invoice, license,
receipt, installation and key history through code rollback and outages. Existing
workloads are never deleted as a payment recovery response. SQL may be checked
separately for compatibility but must not become a second entitlement ledger.

The offline checker must return `liveReady=false` and exit 2 for the pending
inventory. It cannot authenticate an approval. Independent operator/security,
production issuer and owner decisions, plus exact source/artifact evidence, are
required by GF-014 before live. This handoff performs no AWS/provider/secret
mutation or deployment and does not grant one.
