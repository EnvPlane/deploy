# AUD-016: Issuer migration Job ignores imagePullSecrets

Status: confirmed by source/render audit; not fixed.
Priority: P2
Estimated effort: S

## Evidence

activation-issuer/deploy/helm/activation-issuer/templates/migration-job.yaml:22; activation-issuer/deploy/helm/activation-issuer/templates/deployment.yaml:28

Deployment uses configured imagePullSecrets but migration Pod does not. Private-registry migration/install fails unless independent node or SA credentials happen to supply access.

## Implementation prompt for Codex

Share image pull configuration between migration and Deployment. Render-test private image settings and verify private-registry install/upgrade without globally configured registry credentials.

Commit verified iterations with English messages. Report local and live results separately.
