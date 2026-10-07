# Published 0.4.673 upgrade verification

Upgraded envplane/envplane in context envplane using scripts/upgrade-umbrella.sh and the existing durable operator values. Prior revision 34 / 0.4.668 retained as rollback point; rollback trigger is API/frontend readiness or sign-in failure. Upgrade completed revision 35 at 21:30 Europe/Berlin.

Chart digest sha256:58081ded559f0afba313c9a3a47f112bb1c6fa8b39d1a657d0c89658df2aaa02. Manifest source 882b9f879a4753a79694a691346d3809ee6a5224. Frontend source 75df6ae2c5a473a661c469ef2caeaeb6ac0a30a3, installed digest sha256:b877e123878996cf20251bd871b7a9aa3e0c892f57dd842599e83df24a58c60d; ready 1. API ready 1, source/digest unchanged from 0.4.668. Retired singleton Agent/Runner remain scaled zero; no runtime policy/RBAC expansion.

Chrome required ordinary reauthentication; Continue with GitHub returned to Dashboard successfully. Authentication remains github revision 4. No credential or activation change performed. Two active feature tests remain Ready with their existing TTLs. Mobile Cost now measures document/sidebar/workspace 390px at viewport 390px. Remote clusters visibly transition Loading (writes disabled) to Configured, confirming the published loading fix.

A separate nested Settings active-license fingerprint overflow remains (document 570px despite shell 390px). New ticket and local source fix prepared in frontend/ui-regression-673. This does not invalidate the verified shell track fix; the prior mock Free-license fixture did not cover the nested block. Fixed live retest requires a later frontend artifact.

QA verdict 5/5 for upgrade/readiness, normal login and tested prior regressions; full product certification not claimed. CI for the exact artifact and all cryptographic attestations were not independently rerun; prior source tests and packaged immutable manifest were checked. No fresh lifecycle delete, DNS rewrite, tunnel restart or new environment creation in this upgrade turn. Preview DNS, measured FinOps data and approved cleanup remain separate.

Evidence: /private/tmp/envplane-673-mobile-cost.png, /private/tmp/envplane-673-settings-nested-overflow.png, /private/tmp/envplane-673-environments-retained.png.
