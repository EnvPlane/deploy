# Zero-values first-run claim is blocked through documented port-forward access

## Reproduction

1. Install a published umbrella with an otherwise empty operator values file.
2. Port-forward the frontend as documented and submit the managed one-time setup credential.
3. Observe `401` because zero values left the local HTTP setup policy disabled.

## Resolution

The zero-values profile now declares the documented local port-forward origin
and enables the narrowly scoped local HTTP setup transport only while external
access remains disabled. Public ingress, gateway, and HTTPS profiles keep the
strict HTTPS policy.

## Codex implementation prompt

Keep a chart contract test for the zero-values port-forward claim policy. Do
not broaden local HTTP consent to public origins, forwarded headers, OAuth, or
project runtime traffic without an explicit operator access profile.
