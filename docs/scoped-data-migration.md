# Scoped data restore rehearsal (parent-coordinated only)

The helper does not freeze workloads, suspend Flux, create resources, switch
management credentials/gateway/routes, import Helm history or delete source PVs.
Only `inventory` was run live in this iteration. Transfer modes require both
`--parent-coordinated` and the exact private plan `--reviewed-sha256`.

## Exact inventory and separate authentication state

Application plan: `/private/tmp/bethunder-five-pvc-plan-20261008.json`.
Hash: `093d8365aacb837838a9d5875335767979e5dedb8425f3196a3510bd216ba48f`.
Scopes: app-backend, app-frontend, app2-backend, app2-frontend and
envplane-pr-e2e-ui-full-652-1007652. Exactly five bound data claims: backend-data
and mysql-data in app-backend and the feature; backend-data in app2-backend.
Only their five bound PV references are inventoried; 324 historical PVs are not
copied. All original claims and volumes remain on the source for rollback.

Authentication plan is separate: `/private/tmp/bethunder-auth-pvc-plan-20261008.json`.
It inventories only envplane-system's six current auth claims. Parent must pause
all source Agent/Runner writers at the coordinated final phase before exporting
auth data. No token rotation/new identity or management/gateway changes here.
Parent owns logical cluster identity, CA and TLS-server-name configuration.

## Gates before actual backup or restore

1. Parent reviews both private plans and shared Flux ownership (`envplane-prs`
   plus feature Kustomization). Helper refuses unsuspended captured Flux owners;
   it never suspends the shared root itself.
2. Parent coordinates brief write freeze, stops app deployments/CronJobs/Jobs and
   confirms no uncontrolled writers. Raw PVC copy additionally refuses any live
   Pod mounting the claim except the chosen backup helper. **Stop MySQL before
   raw mysql-data copy**; a live file tar is not a consistent database backup.
3. For logical MySQL 8.4 backup, parent enables `super_read_only`; helper verifies
   it before single-transaction, routines/events/triggers dump of MYSQL_DATABASE
   only. Nontransactional tables require separate lock/shutdown review. Root
   password stays inside the container's environment, not CLI arguments/output.
4. Use a private mode-0700 backup directory and age public recipient. Archives
   are exclusively created mode0600 and streamed through age without plaintext
   host dumps. Record encrypted archive SHA256 in the approved private ledger.
   A failed stream leaves an unusable partial artifact; never accept it as backup.
5. Render (`render-helper`) source/target Pod definitions with a reviewed helper
   image **digest**, and explicit target StorageClass. Parent applies only reviewed
   resources. Source helper has read-only PVC mount/no token automount. Target PVC
   is new, retaining capacity/access mode, never volumeName/UID/hostPath/claimRef.
   Read-only source mount may still require helper UID/security-policy review;
   no Pod Security bypass or privileged host mount is created by the helper.
6. Parent restores workload charts from reviewed SCM, not exported live manifests.
   Preserve Helm ownership on target PVCs as required by those charts; candidate
   Flux starts suspended. Review cached image tags and load their exact reviewed
   digests only into candidate; never import source kube-system, auth Secrets or
   Helm release history indiscriminately. No default-context/profile change.

## Available transfer/rehearsal primitives

`python3 scripts/scoped-data-migration.py --help` lists parameters. Common transfer
arguments: `--plan PATH --reviewed-sha256 HASH --parent-coordinated --namespace NAME
--claim CLAIM --pod EXACT_POD --container EXACT_CONTAINER --mount EXACT_MOUNT`.

- `backup-pvc --recipient age1... --archive PATH`: tar whole quiesced claim into
  encrypted archive; exact read-only full mount required (no root/subPath).
- `restore-pvc --identity-file PRIVATE_PATH --archive PATH --archive-sha256 HASH`:
  decrypt only the reviewed artifact, restore only into empty candidate mount;
  refuse existing data and other Pods using target claim.
- `checksum-pvc --side source|target`: helper Python3 computes a deterministic
  file/tree manifest digest, including bytes, paths, directory/link types, mode,
  uid/gid and second-resolution mtime. Unsupported special files/read errors fail.
- `backup-mysql`, `restore-mysql`: observed MySQL 8.4 only, encrypted logical dump;
  restore requires target MYSQL_DATABASE to have zero tables. Parent provides an
  isolated fresh matching instance/credentials, no automatic account recreation.
- `checksum-mysql --side source|target`: streamed deterministic logical dump digest
  without SQL/content printing. Compare hashes, schema/row counts, routines and
  application queries before accepting restore; investigate version/definer/order
  differences rather than declaring mismatching hashes equal.

For raw restore, the reviewed helper must include tar preserving numeric ownership
and Python3; rehearse preservation of links, modes and directories before touching
real data. Archives must come from this approved backup path, not arbitrary tar
inputs. After restore use a read-only helper mount for checksum comparison. Freeze
must remain effective throughout both source/target checksum observations.

No real-data restore rehearsal has run yet. Synthetic tests are not data-integrity
acceptance. Parent orchestrates backup, candidate-only rehearsal, final freeze,
repeat copy/checksums, one-writer Flux ownership handoff and route cutover. Keep
source rollback intact; after candidate writes begin, rollback requires a new
write freeze and reverse data synchronization, not routing back to stale source.
