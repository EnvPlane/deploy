# EnvPilot setup guide

This guide describes the local MVP setup path and the secure bootstrap flow for agent and runner demos.

## Prerequisites

Required:

- Go toolchain matching `go.mod`
- Docker and Docker Compose
- Helm

Optional:

- kubectl
- kind or another Kubernetes cluster
- Flux CLI (required only for `fluxcd` backend)
- PostgreSQL client tools

## Deployment backend strategy

EnvPilot supports two deployment backends:

- Helm Direct (`helm_direct`) applies Helm releases directly and is the default MVP/demo path.
- FluxCD GitOps (`fluxcd`) renders and commits GitOps manifests for Flux reconciliation.

Use Helm Direct for fast demos, PoCs, and setups that do not require a GitOps repository. It requires Kubernetes credentials and `helm` in the control-plane runtime path. FluxCD controllers are not required.

Use FluxCD for enterprise or GitOps-first workflows that require manifest history, review, and pull-based reconciliation. It requires FluxCD installed in the target cluster, GitOps repository write access, a Flux namespace, kustomization configuration, output path, and commit mode.

Security notes:

- Helm Direct performs direct cluster writes through the EnvPilot service identity, so RBAC should be least privilege.
- FluxCD separates GitOps repository permissions from Kubernetes/Flux permissions.
- Runtime bootstrap tokens must not be written into Helm commands, GitOps manifests, logs, or normal API responses.

Recommendation:

- Demo/MVP: prefer `helm_direct`.
- Enterprise/GitOps: use `fluxcd` when GitOps controls are required.

Backend compatibility:

- If `deployment.backend` is omitted, EnvPilot infers backend from existing config values.
- Flux/GitOps operational fields (`gitOpsOutputPath`, `fluxNamespace`, `fluxKustomizationRef`, etc.) imply `fluxcd`.
- Otherwise default is `helm_direct`.

## Local development stack

Start the local stack:

```sh
make dev
```

The compose stack starts:

- PostgreSQL on `localhost:5432`
- Redis on `localhost:6379`
- EnvPilot API/UI on `http://localhost:8080`

Stop the stack:

```sh
make dev-down
```

Clean local demo state:

```sh
make dev-down
docker volume rm envpilot_postgres-data envpilot_redis-data
rm -rf .envpilot/dev
```

## Open the UI

```text
http://localhost:8080
```

Recommended first screens:

1. `Settings -> Product templates -> Services`
2. `Projects`
3. `Environments`
4. `Cost`

## Configure product services

For the default demo, configure:

```text
orders-service
auth-service
payment-service
notification
frontend
postgres
redis
kafka
```

These services drive hybrid override selectors. Create Environment and Hybrid Config screens should use this configured list rather than hardcoded fixtures.

## Create a demo project

Suggested values:

```text
Project: checkout
Repository: https://github.com/example/checkout
Default branch: main
Preview domain: preview.localhost
Default environment mode: hybrid
Default TTL: 48h
```

For Helm Direct:

- Deployment backend: `helm_direct`
- Release pattern: `{{ .project.id }}-{{ .environment.name }}`
- Namespace mode: `dedicated`
- Chart ref/path: `charts/checkout`

For FluxCD:

- Deployment backend: `fluxcd`
- GitOps repository: `https://github.com/example/envpilot-gitops`
- Flux path: `clusters/dev/checkout`
- Commit mode and kustomization settings from your cluster policy

## Configure hybrid mode

Suggested policy:

```text
Base namespace: dev-base

orders-service: override per PR
frontend: override per PR
auth-service: use base
payment-service: use base
postgres: shared dependency
redis: shared dependency
kafka: shared dependency
```

Expected routing:

```text
/orders/*   -> feature namespace
/frontend/* -> feature namespace
/auth/*     -> dev-base
/payments/* -> dev-base
```

## Setup wizard

The setup wizard persists progress locally and through the backend bootstrap session.

Typical flow:

1. SCM credentials
2. Cluster connection
3. Namespace selection
4. Deployment backend selection
5. Backend-specific settings
6. Resource review
7. Service classification
8. Environment variables
9. Domain and routing
10. Templates
11. Policies
12. Final review

Required fields block navigation. Sensitive values are masked after save.

## Agent bootstrap

Generate agent installation instructions from the cluster connection step.

Expected secure behavior:

- Helm command does not include a live registration token.
- A separate sensitive one-time `kubectl create secret ...` command carries the token.
- Re-fetching instructions returns masked token placeholders.
- Agent registration exchanges the registration token for an `agentAuthToken`.
- Heartbeat and resource scan APIs use `Authorization: Bearer <agentAuthToken>`.
- Registration token is not valid after registration.

Agent auth token persistence should be enabled for restart-safe deployments.

### Local minikube: install an agent in a second profile

`envpilot.local` is a host-only ingress name. It must not be used as an agent
control-plane URL from a different minikube profile. The local deployment
instead publishes a chart archive to the Helm client and exposes the API at
`host.minikube.internal:18080` for target-cluster pods.

After `scripts/minikube-up.sh` has deployed the control-plane profile, start a
second profile and prepare the local gateway:

```sh
minikube start -p envpilot-agent-e2e
./scripts/minikube-agent-access.sh start envpilot-agent-e2e
kubectl config use-context envpilot-agent-e2e
```

Then generate the commands in the wizard and run them unchanged, in order:

1. The connectivity preflight must return successfully from the target cluster.
2. Run the sensitive bootstrap Secret command once.
3. Run the Helm command. It repeats the preflight before installing.

The helper transfers `envpilot/api:local`, `envpilot/agent:local`, and
`envpilot/runner:local` to the target profile, serves the packaged
`envpilot-agent` chart on `127.0.0.1:18081` for Helm, and keeps the API
port-forward alive. Stop it only after the agent reports `connected`:

```sh
./scripts/minikube-agent-access.sh stop
```

To execute the exact command copied from the wizard as a repeatable smoke test:

```sh
ENVPILOT_AGENT_HELM_COMMAND='kubectl run ... && helm upgrade ...' \
  ./scripts/minikube-agent-e2e.sh envpilot-agent-e2e
```

For non-local installations set these control-plane environment variables to a
published OCI chart and an address reachable from agent pods:

```text
ENVPILOT_AGENT_HELM_CHART_REF=oci://ghcr.io/envpilot/envpilot-agent
ENVPILOT_AGENT_HELM_CHART_VERSION=<version from the active umbrella compatibility manifest>
ENVPILOT_AGENT_CONTROL_PLANE_URL=https://envpilot.example.com
```

## Runner bootstrap

Generate runner deployment instructions for the project.

Expected secure behavior:

- Helm command references `controlPlane.existingSecret`.
- GitOps manifests do not include live registration tokens.
- Runner config fetch does not use query tokens.
- Runner config fetch accepts bearer project config token only.
- Project config token is one-time use.
- Runner heartbeat uses `runnerAuthToken`, not registration token.

## Local two-minikube successful-environment fixture

Use the fixture below to verify the positive Helm Direct path without weakening
the server-side deploy-readiness gate. It creates or repairs a disposable
project, a healthy base namespace, an Agent and a Runner in the target profile.
It then performs SCM validation, a real resource scan, runner-side chart
preflight, compile, environment creation, target-cluster Helm verification, and
cleanup of the environment/release. The project, Agent, Runner and base
namespace remain so the fixture is fast to rerun.

```sh
# minikube-up builds envpilot/api:local, envpilot/agent:local and
# envpilot/runner:local in the envpilot profile.
./scripts/minikube-up.sh
minikube start -p bethunder-local

# Export a short-lived GitHub or GitLab token only for this command. The script
# sends it to validate-scm and does not store it in the project/session.
export ENVPILOT_E2E_SCM_TOKEN='...'
./scripts/minikube-environment-e2e.sh
unset ENVPILOT_E2E_SCM_TOKEN
```

Alternatively, point the script at a local credential file with one token per
line (a `glpat-...` line for GitLab and/or a `ghp_...`/`github_pat_...` line for
GitHub). The matching token is selected for the configured provider and is
never printed or persisted:

```sh
ENVPILOT_E2E_SCM_TOKEN_FILE=/path/to/scm-tokens \
./scripts/minikube-environment-e2e.sh
```

The default path submits the same public `POST /api/v1/environments` request as
the UI. To additionally run the real Playwright UI flow, first make the
frontend reachable to the local browser and set its base URL:

```sh
ENVPILOT_E2E_SCM_TOKEN='...' \
ENVPILOT_E2E_USE_UI=true \
ENVPILOT_E2E_UI_BASE_URL=http://envpilot.local \
./scripts/minikube-environment-e2e.sh
```

The default fixture uses the canonical repositories
`https://gitlab.com/betario/cms-team/cms.git` (app, `develop`) and
`https://gitlab.com/betario/devops/gitops/fluxcd/clusters.git` (GitOps, `main`).
The script performs a repository readability/write-permission preflight before
installing the Agent or Runner and prints only safe field/code/message
diagnostics. Override `ENVPILOT_E2E_APP_REPOSITORY_URL`,
`ENVPILOT_E2E_GITOPS_REPOSITORY_URL`, their branch variables, and
`ENVPILOT_E2E_SCM_PROVIDER` for another accessible pair of repositories. The
target runner resolves the local chart through
`http://host.minikube.internal:18082`; keep the script running until it
finishes. No external chart registry is required because the script packages
the committed `envpilot-e2e-workload` chart and transfers the locally built
Agent/Runner images into the target profile.

When preparing the bootstrap session, the fixture stores its base namespace in
`selectedBaseNamespaces` (the resource-scan API contract). Do not use the
deprecated `selectedNamespaces` key: it is ignored by the control-plane and
causes resource-scan start to fail before dispatch.

For diagnostics, retain the generated environment with:

```sh
ENVPILOT_E2E_SCM_TOKEN='...' ./scripts/minikube-environment-e2e.sh --keep-environment
```

Do not add SCM, runner registration, or project-config tokens to values files,
shell history, or the fixture project. The script obtains one-time runtime
credentials from the control-plane API, writes them directly into target-cluster
Secrets, and only records safe status/fingerprint metadata in EnvPilot.

## Create demo environment

Suggested values:

```text
Project: checkout
PR/MR: PR-123
Branch: feature/checkout-discount
Commit SHA: abc123
Mode: hybrid
TTL: 48h
```

Expected:

- environment appears in dashboard;
- timeline progresses through GitOps events;
- services table shows PR overrides and base services;
- preview URL is available;
- PR comment contains preview URL if SCM comment integration is configured.

## Cleanup

Cleanup can be triggered by:

- PR close/merge event;
- manual Delete action;
- TTL expiration.

Expected lifecycle:

```text
delete_requested
gitops_delete_pending
terminating
terminated
```

Safety rules:

- protected namespaces cannot be targeted;
- only EnvPilot-labeled resources are deleted;
- base namespace dependencies remain running;
- delete retries are idempotent.

## Validation commands

Run unit and Helm tests:

```sh
go test ./...
helm template envpilot-runner deploy/helm/envpilot-runner
helm template envpilot-agent deploy/helm/envpilot-agent
helm template envpilot-control-plane deploy/helm/envpilot-control-plane
```

Run integration tests:

```sh
make test-integration
```

Run SQL bootstrap claim CAS test with PostgreSQL:

```sh
ENVPILOT_TEST_DATABASE_URL=postgres://envpilot:envpilot@localhost:5432/envpilot?sslmode=disable \
  make test-sql-bootstrap-claim
```

## Demo script

Use the short product narrative:

- [Clean demo flow: PR -> env -> URL -> cleanup](demo-flow-pr-env-url-cleanup.md)
