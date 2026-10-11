# Umbrella 0.4.715 update and live regression

Date: 2026-10-11, Europe/Berlin. Target kind-envplane-readiness-682,
namespace envplane; same explicit private kubeconfig as 0.4.711.

## Installation and backup

Pulled OCI chart 0.4.715, digest
sha256:e31b2dcf3745ca9fefdb9e737d01ae2f424171350d3ea2bf08489cdbbc81081a.
Compatibility API image commit10b37ff50c5b216cb6da3992839a52f3a3900da1
contains f80600c (git ancestry check PASS); frontend exactly68666bb.
API digest251e349c86260bff8b0e9ab81f67df84f92c9270404f021be0cfeb5f8c6eed5c;
frontend digestecb5b021cca2a5ac7ae422f96d73e4b0a5ca2d0a6119bb1884565eb8808ff5a4.
This verifies source linkage, not all hosted CI, signatures or attestations.

Privately backed up complete Helm values/manifests and PostgreSQL custom dump
(22509157 bytes). pg_restore --list accepted the dump (319 list lines).
Initial stdin inspection took longer; temporary Pod file inspection also passed
and only that temporary copy was removed. Host backup remains recoverable.
No full DB restore/DR acceptance inferred.
Upgrade through scripts/upgrade-umbrella.sh --reset-values preserving complete
operator values and sandbox public license key. Helm revision14 deployed.
Four core Pods Ready, zero restarts; envplane.local root HTTP200.

## Live UI regression

| Scenario | Result | Evidence |
| --- | --- | --- |
| License preservation | PASS | Billing local-test-full activation, 1/100 projects, 0/200 feature environments, 0/20 managed clusters; expiry 2026-11-10. |
| Independent SCM setup | PASS | One GitLab webhook panel visible at SCM step1 despite unresolved PVC review; persists into Project settings. No registration/rotation or real provider event invoked. |
| Committed progress versus runtime failure | PASS after transport retry | Next succeeds and reload preserves Project settings step2. Source-identity reconciliation fails separately with safe prerequisite and Retry provisioning; does not misreport a successful save. |
| Local domain relay | FAIL intermittent | First Next returned502; safe DB readback proved next step had NOT committed. Ingress observed premature upstream close for Bootstrap. Explicit retry succeeded. New route ticket remains OPEN. |
| Configuration preview | PASS scoped | Read-only TTL24 request produced valid deterministic fallback, quota/policy allowed, no save/apply. Real AI provider remains disabled; gateway failure UI not exercised in this preview attempt. |
| Source preservation | PASS metadata | Three test-app-base Pods Ready/zero restarts; original backend-data/mysql-data PV bindings unchanged. No SQL grants, password reset, source restart or base PVC writes. |

Private screenshots: /private/tmp/envplane-715-webhook-independent.jpg and
/private/tmp/envplane-715-preview-pass.jpg, outside Git.
Scoped UI QA 4/5; routing reliability and incomplete source preparation keep
overall production acceptance blocked. Deploy-checklist guided backups and
same-release values preservation; Browser Use/QA and debug separated observed
state from runtime/transport results; documentation retains remaining blockers.

## Remaining

Compile/full PVC-copy lifecycle remains blocked by existing MySQL admin/backup
TLS/source access and filesystem source consistency. Executor reconciliation
now advertises the missing authenticated scan identity; do not suppress it.
CNI evidence must be rerun before creation after source prerequisites are met.
Production issuer, real AI, full remote/lifecycle/FinOps/payment/DR acceptance
are not established by this update. New defect:
issues/2026-10-11/715-route-regression/local-domain-relay-drops-bootstrap-response.md.
