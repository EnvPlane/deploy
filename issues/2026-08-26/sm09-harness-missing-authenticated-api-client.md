# SM-09 harness requires an authenticated API client

## Problem

The clean-cluster harness deployed a control plane with managed initial
authentication. Human API routes are intentionally closed before setup, so
the post-port-forward health probe and Bootstrap requests received HTTP 401.

The failure occurred in [umbrella release run
33002071370](https://github.com/envplane/deploy/actions/runs/33002071370).

## Resolution

Generate one random, disposable admin API token in the harness. Put it only in
the runtime-only Helm values file, send it only in the local API client's
Authorization header, and remove the entire Kind cluster during cleanup. This
keeps the live flow behind the normal authorization middleware without putting
a credential in the repository or CI output.
