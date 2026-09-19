# SCM webhook migration runbook

This runbook migrates older manually configured webhook receivers to the control-plane verified
receiver. The preflight is read-only: it reports Secret key names and endpoint state, but never
reads or prints Secret values, signing tokens, or event payloads.

## 1. Read-only preflight

Set the Kubernetes context and namespace, then run:

```sh
ENVPLANE_KUBE_CONTEXT=kind-envplane \
ENVPLANE_WEBHOOK_NAMESPACE=envplane \
ENVPLANE_WEBHOOK_RELEASE=envplane \
./deploy/scripts/scm-webhook-migration-preflight.sh
```

For a project-level report, also set `ENVPLANE_CONTROL_PLANE_URL`,
`ENVPLANE_CONTROL_PLANE_API_TOKEN`, and `ENVPLANE_WEBHOOK_PROJECT_ID`. The API endpoint is
`GET /api/v1/projects/{id}/scm-webhook/migration-preflight` and is read-only and redacted.

## 2. Local tunnel

GitLab cannot deliver to localhost, loopback, a ClusterIP, or a private address. Use an approved
public HTTPS tunnel with a stable hostname, or enable the receiver ingress and expose it through a
public DNS name. Configure the exact callback as:

```text
https://PUBLIC_HOST/api/v1/webhooks/gitlab
```

Run the preflight, then Bootstrap reconcile and **Test delivery**. Keep the old callback until a
successful signed delivery is visible in the status API. A local mode remains not ready until a
public HTTPS endpoint exists.

## 3. Production DNS and TLS

Use a receiver hostname separate from the control-plane hostname. Create an A/AAAA or approved
load-balancer record, issue a certificate containing the hostname, configure the receiver ingress
TLS secret, and verify the status ConfigMap reports DNS, TLS, receiver, and readiness as ready.
Bootstrap checks URL shape, DNS addresses, certificate identity/expiry, `/readyz`, GitLab hook
configuration, signature result, and delivery correlation.

## 4. Migration and compatibility window

1. Install or upgrade the receiver with its stable machine receiver Secret.
2. Run the read-only preflight and record the old Secret key names and callback URL only.
3. Reconcile the project webhook, then run Test delivery.
4. Confirm the redacted status API reports the expected callback and verified delivery.
5. Remove the old remote hook only after the new hook has processed a real event.

The legacy control-plane-token fallback is explicit and expires at
`2026-12-31T23:59:59Z` (`ENVPLANE_WEBHOOK_LEGACY_FALLBACK_UNTIL`). After that deadline the
receiver fails startup unless the dedicated receiver token is configured. This is a removal date,
not a rolling extension: migrate before it and then remove the compatibility setting.

## Receiver status ConfigMap

The receiver status ConfigMap declares endpoint configuration and exposes optional aggregate
observed state. EnvPlane does not update its DNS, TLS, runtime, or readiness fields; an external
controller may publish them for diagnostics. A `pending` value does not block Compile. The
per-project delivery proof is the authoritative compile-gating state, as recorded in the
[webhook readiness proof ADR](https://github.com/EnvPlane/control-plane/blob/main/docs/adr/20260909-webhook-readiness-proof-source.md).

## 5. Rotation

Use the project `rotate-secret` action/API. It updates the encrypted project credential and
reconciles GitLab without restarting the receiver. The control plane accepts the current and
previous credential only during its configured rotation window. Run Test delivery, then verify
the old credential is rejected after the window.

## 6. Rollback

Keep the receiver Secret and TLS Secret during rollback. Roll back the Helm release, preserve the
last known-good callback until the previous release is healthy, and rerun Test delivery. Do not
delete the remote GitLab hook automatically during rollback; remove it only after an operator has
confirmed which release owns it. If the endpoint is unavailable, restore DNS/TLS/ingress first.

## 7. GitLab least privilege

Webhook management normally requires the GitLab `api` scope because creating/updating project
hooks is a write operation. `read_api` is insufficient for hook management. If Note Hook remains
enabled and the receiver performs GitLab membership lookup, its separate membership token needs
only `read_api` and should be limited to the required projects. The receiver must not receive the
control-plane project signing secret; raw events are verified in control-plane. If Note Hook is
disabled, remove the receiver's GitLab API token entirely.
