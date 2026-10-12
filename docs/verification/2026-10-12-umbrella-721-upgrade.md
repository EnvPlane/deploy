# Umbrella 0.4.721 test upgrade

Date: 2026-10-12, Europe/Berlin.

## Published gate evidence

Release run: https://github.com/EnvPlane/deploy/actions/runs/38213092236
Source: `127f4d97d67390e10d9ff366c7e5a558dbcb2a15`.
OCI chart digest: `sha256:643da7ebaa833525e719ac42b3c90b801b030a27adb29a29938a654b40a74707`.

The full successful job log confirms both real browser tests passed:
environment creation (17.6 seconds), and first-run claim/resume/lifecycle,
activation expiry and free-quota recovery (50.3 seconds). The job explicitly
reports `SM-09 private-registry lifecycle gate passed`. The prior anonymous
identity discovery 401 assertion no longer fails this disposable gate.

## Existing test installation

Only `kind-envplane-readiness-682`, release/namespace `envplane`, upgraded
from umbrella 0.4.718 revision 16 to 0.4.721 revision 17. Complete user values
and previous manifests were saved. PostgreSQL custom-format backup was
33,087,087 bytes; its 319-line archive catalog was verified with PostgreSQL 17
in a disposable no-network container with a read-only backup mount.
The first catalog verification through kubectl stdin timed out after producing
the catalog; the successful local-container check was used instead.

Private rollback artifacts: `/private/tmp/envplane-upgrade-721.ToNcWu`.
These may contain sensitive configuration; they are not committed.

The standard `scripts/upgrade-umbrella.sh` used complete saved values and
`--reset-values`. No old image pin overrides were present. Helm reports deployed.

## Post-upgrade checks

- API, frontend, PostgreSQL and Redis pods: Running and Ready.
- API image: `sha256:10979783dba8351e36d42ebc32d1601e4f3f85e50cf2b892cbd204052b1314e6`.
- Frontend image: `sha256:a651a459a7cb0d0f47b5b0fb926440496a066f7d10f0d88914baf75bc16d8f51`.
- `http://envplane.local/`: HTTP 200.
- No other cluster, test-app workload or application PVC was changed by this
  upgrade. Project executors remain managed by the normal reconciler.

## Boundaries

Hosted disposable gate evidence is not a new OAuth/PVC-copy approval or full
regression of this existing tenant. Existing source-access approvals and
production-readiness blockers require their separate live acceptance checks.
