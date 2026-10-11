# Local domain relay intermittently drops Bootstrap progress response

Priority: P1 local QA access reliability. Status: OPEN.
Observed: umbrella 0.4.715 revision14, kind-envplane-readiness-682,
tenant default, project test-app. Existing routing-only Minikube envplane
ingress proxies envplane.local through host.docker.internal:3000 to supervised
kind frontend port-forward. This is not production ingress acceptance.

## Evidence

First Next from SCM returned HTTP 502 and unsaved draft. Safe DB readback
confirmed current_step0/statusreviewed/runtimefailed: requested step1 had NOT
committed. Retry advanced to Project settings, and reload preserved step2 UI
(current_step1). Runtime source-identity failure is now separate and actionable.

Routing ingress logged upstream prematurely closed connection for the Bootstrap
route, upstream http://192.168.65.254:3000. Core Pods Ready, zero restarts;
frontend transport counters for ECONNRESET/ECONNREFUSED/ETIMEDOUT were zero in
the inspected window. The failing routing hop is observed; underlying reason
(keepalive, forwarding lifecycle, upstream cancellation) is NOT isolated.
This expands the earlier configuration-preview 502 investigation, not proof
that the control-plane progress fix regressed.

## Codex implementation prompt

Reproduce a first request after idle/rollout through the exact local relay and
direct loopback route with safe status/correlation diagnostics. Inspect forwarded
connection lifecycle and proxy keepalive compatibility; isolate actual cause
before patching. Make routing restoration resilient without weakening OAuth,
TLS or network isolation. Never solve this by enabling automatic non-idempotent
POST/PATCH retries: read durable progress before explicitly resubmitting.
Preserve original cluster/application/PVC data and the active license. Test
idle, API/frontend rollout, partial upstream response, authenticated progress
and read-only preview. Record local versus deployed acceptance separately.

Acceptance: controlled relay reproduction no longer loses responses; a real
outage remains actionable and does not imply a rolled-back committed write.
Do not publish request bodies, cookies, authorization headers or raw logs.
