# AUD-017: CI rebuilds dependencies before checking committed vendoring

Status: confirmed by source/render audit; not fixed.
Priority: P2
Estimated effort: S

## Evidence

deploy/.github/workflows/ci.yaml:63-84; deploy/scripts/check-vendored-chart-drift.sh

CI dependency build rewrites packages before the later drift check. It can conceal stale committed packages; running the drift check directly currently fails for agent 0.2.29.

## Implementation prompt for Codex

Check committed chart payloads before rebuilding, or fail when dependency build changes tracked package state. Add a regression fixture with deliberately stale archive and fresh source; CI must reject it.

Commit verified iterations with English messages. Report local and live results separately.
