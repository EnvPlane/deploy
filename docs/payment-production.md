# PAY-012 deployment handoff

Production payment rollout is blocked. This document does not authorize Helm
install/upgrade, infrastructure or Secret changes, provider provisioning, charges,
refunds or push. The current seller provider runtime is test-only. Sandbox
foundation and local SQL restoration are not production readiness.

Use the seller-owned activation-issuer chart, not the customer umbrella or a second
entitlement service. The authoritative procedures, pending sign-offs and local
evidence live in sibling control-plane:

- `docs/payment-production/runbook.md`
- `docs/payment-production/sign-off.pending.json`
- `docs/payment-production/verification.md`
- `scripts/check-payment-production-readiness.py`
- `scripts/rehearse-payment-restore.py`

From an EnvPlane workspace containing deploy, contracts, control-plane and
activation-issuer, the non-mutating review commands are:

```sh
python3 ../control-plane/scripts/check-payment-production-readiness.py ../control-plane/docs/payment-production/sign-off.pending.json
helm template pay012-review ../activation-issuer/deploy/helm/activation-issuer --namespace pay012-review --set image.repository=ghcr.io/envplane/activation-issuer --set image.tag=review-only --set existingSecret=operator-managed-config-reference
```

The checker exits 2 for blocked launch, including fully self-asserted approval
JSON. Helm output is a render-only template with review placeholders. It must not
be applied. A separately reviewed deployment gate must authenticate approvals and
consume exact component/contract/chart versions before any live launch.

| Dependency | Required operator proof before deployment |
| --- | --- |
| PostgreSQL | permanent encrypted store, verify-full hostname/CA, capacity/failover, retained ledger and receipt history, approved RPO/RTO, encrypted backup/PITR and isolated restore |
| protected signer | private-key custody, exact Ed25519 compatibility/payload limits, scoped signing identity, public verification history, tested rotation/rollback and outages |
| Secret-managed config | separate test/live resources and versions, approved runtime injection/synchronization, audited rotation/rollback, no plaintext Helm/CI artifacts |
| ingress/network | verified public raw-body webhook route only; private internal/operator/signer routes; no customer-cluster network access |
| operations | existing transactional workers/reconciliation/DLQ, read-only monitoring identity, per-replica counter scrape, delivered and acknowledged alerts, reviewed retention/PII policy |
| commercial/support | confirmed seller/invoice/tax details, independent owner/issuer reviews, controlled PAY-011 real sandbox evidence, explicit support readiness before SLA |

The existing chart uses external database/signer/Secret references, two serving
replicas and a migration hook. It does not provision these dependencies, public
ingress, network policies or alert delivery. Migration/runtime currently share a
Secret reference; separate least-privilege database identities and read-only
monitoring credentials remain tracked implementation gates. Do not hide these
gaps by treating healthy Pods as proof.

Recover into a new isolated database with one approved writer. Compare financial
history and dedup receipts before enabling bounded canonical GET reconciliation.
Never run source and recovered ledgers as competing entitlement authorities.
Rollback retains ledger/schema/public-key history and pauses candidate workers;
do not reset payment attempts or delete customer workloads during outages.

This iteration contains documentation only in deploy. No deployment, Kubernetes,
provider or Secret state was inspected or changed.
