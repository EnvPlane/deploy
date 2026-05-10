# EnvPilot Deploy

Deployment and release artifacts for EnvPilot.

## Scope

- Helm charts for control plane, agent, and runner.
- Local Docker Compose development deployment.
- Container Dockerfile baseline.
- Setup documentation.

## Source Origin

This repository was split from:

- `deploy/helm/*`
- `docker-compose.yml`
- root `Dockerfile`
- deployment setup docs

## Notes

Packaged chart archives (`*.tgz`) and local credentials are intentionally not copied. Build and package charts from source as part of release automation.
