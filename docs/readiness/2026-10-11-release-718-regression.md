# Candidate 0.4.718 regression results

## Upgrade and retained recovery material

- Target: kind-envplane-readiness-682, release envplane in namespace envplane.
- Upgrade completed at revision 16 using upgrade-umbrella.sh with reset-values
  and complete pre-upgrade operator values. Previous version: 0.4.717, revision 15.
- OCI archive digest: sha256:c694cdb295d19f9c0265cf6652772ac793d2e6e09d3bfc4c3b382b9dca7f408d.
- API source: 729c9b704ebd8d51aac44537d817db5714840167; running digest:
  sha256:e03e109e4fa7d3fde495cca2fc2f3670fe02e06677f38e3f92a39e4748a884a9.
- Complete values, previous manifest and approximately 24 MiB PostgreSQL custom
  dump are retained privately in /private/tmp/envplane-718-verification.EL14F2cT.
  Streaming pg_restore list validation encountered a kubectl exec transport
  timeout; copying the saved archive to a temporary Pod file and running
  pg_restore --list succeeded. This establishes readable archive structure,
  not a full DR restore. Only the temporary Pod copy was deleted afterward.
- Rollback trigger: API readiness/authentication loss or corruption of bootstrap
  data. Preserve current DB and inspect migrations before reverting writers;
  a Helm rollback alone is not a database rollback.

## Verified

- Hosted Go CI run 38144239274 for exact API source completed successfully.
- API, frontend, PostgreSQL and Redis Ready with zero observed restarts.
- Local domain returned HTTP 200; authenticated Chrome Bootstrap session survived.
- Live API OpenAPI SHA256:
  87e4fdc0fcefbfe2d0627a53f43442d3792eaca068d29fbc7e1a96de2ed0a8cd,
  matching published contracts v0.1.112. Verified inside the API Pod; frontend
  /openapi.json is not the API endpoint and returned 404.
- Step 5 now publishes an exact source-access review before target credentials
  are configured in step 9. Refresh source profile returns the same review.
- Base backend/frontend/MySQL remain Ready; all three base PVCs remain Bound,
  including retained mysql-data and fresh mysql-data-fresh-715.

## Remaining gates

- Source review pvc-source-onboarding-80020e8bef76cbc12101edff is pending approval;
  includes fresh MySQL and backend-data filesystem source. No approval was made,
  no root-helper allowance selected, and no source RBAC was expanded.
- Project executor reconciliation reports failure while source access is pending.
  Diagnose any remaining failure after the separately reviewed permission gate.
- CNI enforcement evidence is stale. Compile and full native backup/restore
  remain unverified; no copied-data success is inferred from source review.
- SCM shows current endpoint/receiver ready and historical verified delivery;
  a new post-upgrade GitLab delivery was not triggered in this regression.
- QA verdict for the tested source-review path: 4/5. The original step-order
  defect is closed, but UI exposes a generic executor failure alongside the
  pending permission review. Full product readiness is not established.

No application data, existing PVC, remote-cluster infrastructure or credentials
were modified by these regression checks.
