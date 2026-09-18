# Ingress API routing bypasses the authenticated frontend proxy

## Problem

The umbrella access resources route `/api` directly to the control-plane. The
frontend is the same-origin API proxy: its Next.js rewrite forwards `/api/*`
to the control-plane while retaining the browser session and CSRF behaviour.
Direct routing bypasses that proxy, so an authenticated browser receives an
API-token error or times out when using the public Ingress or Gateway URL.

## Required implementation

Route `/api` to the frontend service for both `access.mode=ingress` and
`access.mode=gateway`. Keep `/auth` and `/webhook` routed directly to the
control-plane. Add a chart contract that proves the API path resolves to the
frontend while the direct control-plane paths remain unchanged.

## Acceptance criteria

- An authenticated same-origin browser request to `/api/v1/projects` reaches
  the frontend rewrite and succeeds with its session.
- OAuth callbacks under `/auth` and webhook receivers under `/webhook` still
  reach the control-plane directly.
- The rendered Ingress and HTTPRoute are covered by automated chart tests.
