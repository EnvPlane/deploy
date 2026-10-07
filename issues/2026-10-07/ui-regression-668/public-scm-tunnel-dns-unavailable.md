# Configured public SCM tunnel hostname no longer resolves

Status: live external prerequisite blocked on published 0.4.668. No application-code defect established.

## Evidence

Settings Public URL is https://clearly-con-converted-childhood.trycloudflare.com. Opening this exact origin in Chrome returns ERR_NAME_NOT_RESOLVED and DNS_PROBE_FINISHED_NXDOMAIN. Bootstrap SCM webhook diagnostics independently reports callback DNS failed, current Endpoint/DNS Failed and historical delivery Verified. Compile remains blocked; prior successful delivery is not current reachability.

Freshly reloading the GitLab envplane/backend Webhooks page shows the matching callback https://clearly-con-converted-childhood.trycloudflare.com/api/v1/webhook-receiver/gitlab?project=app&tenant=default, Merge request events and Comments enabled, SSL verification enabled. The previously loaded GitLab tab had shown an older hostname and a historical HTTP 202 toast; neither is current evidence after reload.

No webhook event, registration, rotation, DNS edit or new public exposure was initiated. The exact cause of tunnel loss is not inferred from DNS alone.

## Acceptance and Codex prompt

With explicit authority for network publication, restore an operator-owned reachable public HTTPS SCM endpoint or approved temporary tunnel. Preserve authentication and certificate verification. Update the profile/provider callback through normal authorized UI flow if the hostname changes, then confirm current endpoint readiness and a fresh signed GitLab delivery before Compile. Do not weaken verification or reuse the historical proof to bypass readiness. Keep preview-domain DNS as a separate issue.

Evidence: /private/tmp/envplane-668-scm-endpoint-dns-failure.png, /private/tmp/envplane-668-scm-webhook-not-ready.png.
