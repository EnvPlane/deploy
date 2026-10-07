# Configured preview domain is not reachable in the live client

Status: external DNS prerequisite unresolved; domain clarification requested.

The new feature e2e-ui-full-652-1007652 became Ready, with three Running/Ready
Pods and both new PVCs Bound on envplane-local-path. Chrome opened the configured
frontend URL http://pr-1007652-frontend.preview.company.com/ and reported
ERR_NAME_NOT_RESOLVED. No DNS, hosts file, tunnel or Ingress mapping was changed.

Codex prompt: establish the administrator-owned preview domain and reachable
Ingress endpoint for bethunder-local before an end-to-end browser routing claim.
Keep workload readiness separate from DNS/TLS/public reachability; current UI
already warns about that distinction. Do not repoint a domain or publish an
internal app without explicit authority. Verify both frontend and backend URLs
through a browser after configuration and preserve the environment snapshot
contract: changing project configuration alone does not rewrite old snapshots.

This is a deployment prerequisite, not proof of an Ingress or storage defect.
