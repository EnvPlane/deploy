# Project Agent image default lags the published singleton Agent

Status: release 0.4.650 verified affected; local upgrade uses explicit corrected
tag; publication updater fixed with regression test; next release retest pending.

The umbrella pins singleton Agent cad8b60, but control-plane.agentBootstrap.image
still points at 7e03dde. Project installers therefore miss storage provider flags
even though the top-level deployment is current. API/frontend revisions in this
release are correct. The runtime-image updater only changed the child image.

Codex prompt: atomically update the control-plane project Agent default whenever
the published agent component pin changes. Require both expected blocks, fail
without modifying the values file if either is missing, preserve all other
runtime image blocks, and add updater isolation/synchronization tests. Keep
explicit installation overrides supported; do not patch cluster RBAC or PVCs.
