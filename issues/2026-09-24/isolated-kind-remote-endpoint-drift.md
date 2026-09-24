# Refresh isolated Kind RemoteCluster endpoint after cluster recreation

## Observed

On the isolated umbrella `0.4.400` fixture, the remote Kind control-plane
container was recreated with address `172.18.0.2`, while RemoteCluster
`e2e-remote-353` and its referenced kubeconfig still used `172.18.0.4`.
The next RemoteCluster repair reported `remote endpoint or credential access
failed`; the project stayed not-ready although its Agent and Runner were
online.

Updating the kubeconfig Secret and the RemoteCluster Kubernetes endpoint to
the current Kind address allowed reconciliation to complete and restored project
readiness.

## Codex implementation prompt

Make the reusable isolated two-Kind E2E fixture derive and reconcile the
current remote Kind API address whenever it is set up or resumed. Update both
the management-cluster kubeconfig Secret and the RemoteCluster endpoint through
the supported API, without reading or logging credential contents. Add a
contract or fixture test that simulates a changed remote Kind container address
and requires the project to recover to a fresh healthy RemoteCluster state.
Keep this behavior strictly scoped to the explicitly named isolated E2E
contexts; do not introduce automatic endpoint rewriting for user-managed
clusters.

## Verification

- `0.4.400` isolated UI tests passed after the scoped fixture correction:
  dashboard/project filter, deploy-ready session secrecy, and create/delete
  lifecycle of an automatically generated disposable environment.
- The corrected project `e2e-remote-workload-372` reports `ready=true` and
  `e2e-remote-353` reports `healthy`.

## Status

Open: the live fixture was repaired manually; a durable fixture-level refresh
has not yet been implemented.
