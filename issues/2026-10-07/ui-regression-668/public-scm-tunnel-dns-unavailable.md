# Configured public SCM tunnel hostname no longer resolves

Status: restored and live verified on published 0.4.668. Fresh provider-side MR delivery and job processing verified at 20:32 Europe/Berlin. No application-code defect established.

## Recovery verification

On explicit user request, started the existing cloudflared binary in exec session 92994 with `cloudflared tunnel --url http://127.0.0.1:80 --http-host-header envplane.local --no-autoupdate`. No older cloudflared process was present; the existing minikube tunnel was left unchanged.

New temporary origin: https://charm-solve-medications-dryer.trycloudflare.com. Local and public roots returned HTTP 200 with normal TLS validation. Saved the new Public SCM URL through Settings, then registered the existing project app webhook through Bootstrap. Reloaded GitLab confirms hook 88963028 uses this callback with `project=app&tenant=default`, MR and Comments events, and SSL verification enabled.

Bootstrap Test delivery produced a fresh signed probe at 20:27:49 Europe/Berlin: delivery/signature Verified and Endpoint/DNS/TLS/Receiver Ready. This is a self-issued probe, not a real GitLab MR event. No job was created. Provider-side MR testing is awaiting action-time approval because a closed MR payload can trigger cleanup.

Compile succeeded: the project overview shows Deploy-ready and compiled configuration v7. Simulate PR with dry-run commit checked returned valid, 15 templates/files and simulated status at `app/simulations/20261007T182831Z`. No actual GitOps commit or feature environment was created by this simulation. Preview DNS and CNI enforcement remain separate unverified prerequisites.

QA verdict: 5/5 for the tested endpoint restoration, registration, signed probe, compile and dry-run path only; not full lifecycle certification. Authentication, managed runtime endpoint, credentials and baseline workloads were not changed. The quick tunnel is temporary and has no uptime guarantee; its process must remain running.

Evidence: /private/tmp/envplane-668-scm-restored.png and /private/tmp/envplane-668-gitlab-webhook-restored.png.

## Fresh provider-side MR test

After the user confirmed the explained MR-test/cleanup risk, GitLab hook 88963028 Test / Merge request events returned HTTP 202. EnvPlane showed a fresh verified delivery at 20:32:16 Europe/Berlin, verified signature, and job `job-bfee3ee98230d75c6f2543042932f890`. The Jobs UI confirmed succeeded, type delete_environment, target `e2e-webhook-live-294-20260919-gitlab-243dfdce`, consistent with the selected closed test MR. This confirms real GitLab delivery and successful processing of the cleanup event, not new feature-environment creation or physical removal of previously absent resources.

The Environments UI still shows `e2e-ui-full-652-1007652` Ready with TTL 24h and the same two Terminated records. No additional UI deletion or Recreate was initiated. QA verdict: 5/5 for the tested provider delivery, fresh diagnostics and job correlation. No new defect found. Preview URL DNS, CNI enforcement and fresh creation lifecycle remain outside this result.

Provider evidence: /private/tmp/envplane-668-gitlab-mr-202.png and /private/tmp/envplane-668-gitlab-mr-job.png.

## Evidence

Settings Public URL is https://clearly-con-converted-childhood.trycloudflare.com. Opening this exact origin in Chrome returns ERR_NAME_NOT_RESOLVED and DNS_PROBE_FINISHED_NXDOMAIN. Bootstrap SCM webhook diagnostics independently reports callback DNS failed, current Endpoint/DNS Failed and historical delivery Verified. Compile remains blocked; prior successful delivery is not current reachability.

Freshly reloading the GitLab envplane/backend Webhooks page shows the matching callback https://clearly-con-converted-childhood.trycloudflare.com/api/v1/webhook-receiver/gitlab?project=app&tenant=default, Merge request events and Comments enabled, SSL verification enabled. The previously loaded GitLab tab had shown an older hostname and a historical HTTP 202 toast; neither is current evidence after reload.

No webhook event, registration, rotation, DNS edit or new public exposure was initiated. The exact cause of tunnel loss is not inferred from DNS alone.

## Acceptance and Codex prompt

With explicit authority for network publication, restore an operator-owned reachable public HTTPS SCM endpoint or approved temporary tunnel. Preserve authentication and certificate verification. Update the profile/provider callback through normal authorized UI flow if the hostname changes, then confirm current endpoint readiness and a fresh signed GitLab delivery before Compile. Do not weaken verification or reuse the historical proof to bypass readiness. Keep preview-domain DNS as a separate issue.

Evidence: /private/tmp/envplane-668-scm-endpoint-dns-failure.png, /private/tmp/envplane-668-scm-webhook-not-ready.png.
