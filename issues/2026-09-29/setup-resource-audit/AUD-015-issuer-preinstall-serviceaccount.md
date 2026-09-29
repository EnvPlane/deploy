# AUD-015: Issuer migration pre-install hook requires an account created after the hook

Status: confirmed by source/render audit; not fixed.
Priority: P1
Estimated effort: S

## Evidence

activation-issuer/deploy/helm/activation-issuer/templates/migration-job.yaml:12,24; activation-issuer/deploy/helm/activation-issuer/templates/serviceaccount.yaml:1

Migration is pre-install but uses the ordinary chart-created ServiceAccount. On fresh installation it cannot create a Pod until that account exists; upgrade on a populated namespace can mask the defect.

## Implementation prompt for Codex

Give migration a separately ordered hook-owned account with bounded lifecycle or use an explicitly required preexisting account. Test a genuinely empty namespace and ordinary upgrade; keep migrations ahead of serving traffic.

Commit verified iterations with English messages. Report local and live results separately.
