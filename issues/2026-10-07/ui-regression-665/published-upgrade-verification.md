# Published umbrella 0.4.665 upgrade and UI regression

Date: 2026-10-07, Europe/Berlin.

## Upgrade

Upgraded context envplane, release envplane/envplane using scripts/upgrade-umbrella.sh and local-platform/envplane-zero-setup-license-values.yaml. Release revision 33, chart/app version 0.4.665, deployed. Previous revision 32 is the Helm rollback reference; its stored chart does not include the temporary local hotfix overrides.

Umbrella OCI digest: sha256:1b8d514ce073b4de38e3b0e36cc2cef726d92092b522588486087efed673f369.

Local hotfix deployment images have been replaced with published artifacts:

- API: ghcr.io/envplane/api@sha256:8c3395f9e0fe143e9bf3720a2fb2f700bc4ebbb26a52631cb02d38909ad10045, manifest source tag sha-f8b22f30e60cd0d58eb4a23cf807ace417906b53.
- Frontend: ghcr.io/envplane/frontend@sha256:6696817cac43b90786c72e2ded5ff652ae0f03dbd9e1708ea29ce1d17ab11fc7, manifest source tag sha-c700b9274acdd9aef2fafa2ef364eb13b508d618.

Both deployments ready. Git ancestry confirms API includes fe126cb management-runtime recovery and bc8a38f provisioning attempt timeout; frontend includes 0606cdb Flux-control deduplication. This verifies source inclusion and actual image pins, not a separate cryptographic attestation verification.

## Runtime and live Chrome evidence

- Existing management project Agent/Runner remained 1/1 Running with zero restarts; auth generation stayed 2.
- Safe PostgreSQL readback confirmed fresh online heartbeats and renewed Runner lease after the published API rollout. No credentials queried or printed.
- Existing OAuth session, enterprise activation and Settings-managed Anthropic credential retained.
- Bootstrap has one GitOps output-path, Flux namespace and commit-mode control; stored TTL remains 24.
- AI typed preview copied TTL 48; Reject restored TTL 24 without Compile or repository/config mutation.
- FinOps memory step=1; negative memory rejected and focused; reload preserved stored memory=0 and TTL=24.
- Recreate only of e2e-ui-full-652-1007652 completed Ready on published API. Backend/frontend/MySQL Ready; historical creation date retained; active TTL 24h. No false 30-minute timeout observed.
- Pin persisted after reload; Unpin restored active expiration. Test left Ready/unpinned.
- No cleanup/purge, RBAC expansion, credentials rotation, DNS/tunnel changes or base-workload changes performed this pass.

## Limits

This bounded published-release regression does not rerun zero-install, Terminated-to-Recreate cleanup, every AI-provider agent, external webhook delivery, CNI enforcement or full headless real-cluster suite. Terminated-to-Recreate was previously verified with the same fixes in local hotfixes. Existing preview DNS blocker remains open; reachability was not re-certified here. QA score for tested UI paths: 4/5, with no new defects observed.

Evidence screenshot: /private/tmp/envplane-665-published-recreate-ready.png.
