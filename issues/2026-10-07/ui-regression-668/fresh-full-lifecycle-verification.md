# Fresh Full lifecycle UI verification on published 0.4.668

Status: creation/Recreate and TTL/Pin verified; cleanup awaiting explicit approval. No new application-code defect established.

## Observed flow

Created only `e2e-ui-full-668-1007668` for project app, branch main, synthetic MR 1007668, Full mode and TTL 2h through Environments UI. Initial executor provisioning failed before workload publication. Bootstrap exposed the exact missing installer get on Kustomization `flux-system/e2e-ui-full-668-1007668.generic`; SCM remained Verified.

With explicit user approval, appended only this resourceName to existing Role `flux-system/envplane-project-app-feature-flux-reader-parent` using a resourceVersion test. Installer identity `envplane-system/envplane-remote-cluster-bethunder-local` can get the approved object; get on `unapproved-668-check` remains denied. No namespace-wide privilege granted. This is an operator migration of the previously documented exact-name legacy profile, not an automatic permission expansion or new product fix.

Bootstrap Retry executor provisioning restored Deploy-ready. Environments Recreate used the recorded template snapshot `project-config-9a78f1728264fa0a338a8b853cc4adc6`, digest `sha256:48fd4b79ec4e03f874e07cd3a85d2ead2d392368ee117c33b074e8905a00383f`. The asynchronous flow transitioned to Creating then Ready by 20:39 Europe/Berlin. Backend, frontend and mysql rows all Ready; Kubernetes diagnosis healthy. Initial PVC FailedMount warnings were historical, followed by normal workload startup; no new persistent storage failure established.

Extend TTL moved expiration forward by two hours. Pin showed expiration paused and survived page reload. Unpin resumed TTL with expiration 22:40:07 Europe/Berlin. No unrelated environment action was initiated.

Global GitOps showed configured repository/path with unknown controller/applied revision and explicitly no authorized repair. Project GitOps retained the configured Flux path. Services showed two configured components but an empty base catalog, correctly explaining that this is not evidence of absent feature workloads.

## Boundaries and follow-up

QA 5/5 for tested recovery/Recreate, Ready services and TTL/Pin persistence only; not complete product certification. Initial unmodified legacy installer could not create this new name. Preview URL DNS/TLS/reachability and CNI enforcement are not certified by Ready. Synthetic MR metadata is not proof of a real MR creation event. Cleanup is pending action-time permission.

Implementation/operations prompt: preserve exact-name project Agent access. For durable operator onboarding, use the existing opt-in installer Flux status-reader namespace profile only with explicit administrator review; do not silently escalate scope or hardcode this test name into shipped defaults. Continue cleanup through normal UI, verify Terminated and absence of target resources, then obtain separate authority before deleting history.

Evidence: /private/tmp/envplane-668-new-environment-failed.png, /private/tmp/envplane-668-flux-exact-name-blocker.png, /private/tmp/envplane-668-new-full-ready.png, /private/tmp/envplane-668-ttl-unpin-retained.png.

## Subsequent UI checks at 20:43–20:46 Europe/Berlin

The new environment remains Ready. Flux GitRepository and Kustomization are ready. Warning event filtering shows the historical mysql readiness probe warning without classifying the current workload as failed; Normal filtering shows only normal events. Restored All using the visible option label. A select-by-value attempt with `All` failed because the actual value is `all`; this was a test-driver selector mismatch, not an application defect.

Opened the exact frontend preview link exposed by the UI. Chrome reports ERR_NAME_NOT_RESOLVED / DNS_PROBE_FINISHED_NXDOMAIN for `pr-1007668-frontend.preview.company.com`. This confirms the previously recorded preview DNS blocker also affects the fresh namespace. No DNS, ingress or security settings changed. Ready is not external-route certification.

Cost reflects two active environments: estimated tenant-wide daily total approximately EUR 2.40, idle zero. Explain and optimization correctly return unknown forecast/incomplete measured price or usage data without substituting estimates or fabricating savings. Switching the global project selector to envplane loads its zero/default cost policy and effective max 200; switching back to test-app restores app policy max 3, TTL 24h and idle timeout 2h. No policy or currency save was performed. Tenant-wide charts remain explicitly labeled as tenant-wide. Console error log empty.

QA verdict: 5/5 for event filtering, fresh Flux readiness and tested FinOps scope/evidence behavior; external preview accessibility blocked. No new application defect established. Cleanup still awaits the separate deletion confirmation; do not infer permission from a generic request to continue tests.

Additional evidence: /private/tmp/envplane-668-preview-dns-failed.png and /private/tmp/envplane-668-finops-two-environments.png.
