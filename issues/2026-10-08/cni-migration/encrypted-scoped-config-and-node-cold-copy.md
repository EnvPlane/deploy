# Encrypted projected config and cold node transfer for Restricted runtimes

The reviewed candidate is prepared with five app and six runtime-auth PVCs.
Source runtime namespace enforces Restricted PSA. Default-root helper Pods must
not be introduced there or enabled by lowering PSA. Node administrator authority
was granted as part of scoped application/data migration.

## Local implementation

- `scoped-config-snapshot.py` exports the reviewed exact namespaces into age
  encryption without plaintext host files or output. It strips source identities,
  Service allocations, auto SA-token refs and all but current deployed Helm
  release records. Target app/runtime replicas are zero; Flux remains suspended.
- Candidate Flux controller identities are kept, not replaced with source Helm
  controller SAs. SSA conflicts fail closed; unrelated fields are not forced.
- `private-candidate-credential.py` seals the target SA kubeconfig with its actual
  CA and explicit TLS server name. No token/raw credential output.
- `scoped-node-data-transfer.py` uses exact PVC/PV bindings and fresh target paths,
  verifies both cluster/node identities, stopped writers/Flux/Jobs, unused claims
  and empty destination, then encrypts raw cold tar and restores only into the
  reviewed candidate. All content/mode/uid/gid/mtime digests must match before
  accepting it. It uses `docker exec -i`, not PTY SSH, for binary safety.
- Source paths, permissions, PVCs and PVs remain unchanged; no broad root export,
  no historical PV copying, no source deletion or automatic stale-data rollback.

## Codex implementation prompt

Require candidate image/controller/RBAC/TLS preflight before source write freeze.
Execute the exact eleven-claim backup/restore, then verify MySQL, frontend/backend,
same-namespace/base routes and enforcing NetworkPolicy. Apply only a reviewed
Flux policy patch for this existing restricted-mode feature; prove reconciliation
does not restore the old broken policy. Restore normal runtimes and trusted
readiness/reporting on candidate. Keep source stopped but intact after successful
cutover; any rollback after candidate writes requires reverse data reconciliation.
Do not push source commits or expose Secrets, activation codes or data contents.
