# Live test MySQL TLS and backup preparation

Scope: kind-envplane-readiness-682 / test-app-base / mysql; project test-app,
tenant default. User authorized the next preparation step after replacing only
the test database. No old datadir recovery or deletion was performed.

## Verified

- Reviewed administrator preparation digest:
  b6a201ad336a44acbe22b48256f45c0b1801d6f81d8196fd42f460aef69c6b22.
- Protected pre-change complete values, logical app database dump, reviewed plan
  and preparation receipt:
  /private/tmp/envplane-mysql-tls-715.0p0go5cc (operator-only files).
- Source PVC mysql-data-fresh-715; UID/PV binding unchanged throughout preparation.
- TLS Secret ep-mysql-tls-1330df3fa2d4616009e3, public CA Secret
  ep-mysql-ca-1330df3fa2d4616009e3, key ca.crt.
- Verified hostname mysql.test-app-base.svc; TLSv1.2/TLSv1.3 configuration.
- Backup Secret ep-mysql-backup-1330df3fa2d4616009e3, keys username/password;
  separate user ep_backup_1330df3fa2d4616009e3 requires SSL.
- Exact privileges: SELECT/SHOW VIEW/TRIGGER/EVENT on app schema;
  SHOW_ROUTINE/BACKUP_ADMIN globally, no ALL/GRANT OPTION/global SELECT.
- VERIFY_IDENTITY session, expected exact grants, LOCK INSTANCE FOR BACKUP and
  UNLOCK verified before and after Helm reconciliation.
- Negative tests: plaintext backup login rejected; TLS with 127.0.0.1 instead of
  the certificate hostname rejected. Root and application SQL login still pass.
- Full Helm values persist mysql.tls.existingSecretName, same root Secret and
  fresh claim. Release test-app-base revision 5, chart 0.1.5; no reuse-values.
- mysql-0, backend and frontend Ready, zero restarts at observation.
- Original mysql-data remains bound to original PV; backend-data unchanged.
- No credential values, CA private signer or database contents committed.

## Limits and next acceptance

This is privileged preparation proof, not a completed product/UI onboarding or
successful data-copy claim. Rescan authenticated resource identity, save safe
source profile references, complete separate copy approval/permissions and fresh
CNI proof, then test actual logical backup/restore and isolated credentials/data.
Existing filesystem backend-data requires its own writer-stop/fence review.
Server certificate expires after 90 days, CA after 365 days; production automatic
renewal/controller integration remains open. Preserve original/fresh volumes and
credentials; deleting retained data requires separate explicit authorization.
