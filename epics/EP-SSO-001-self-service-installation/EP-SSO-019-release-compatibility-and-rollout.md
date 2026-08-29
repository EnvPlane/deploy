# EP-SSO-019: Ввести rollout и compatibility policy нового install flow

Зависит от: EP-SSO-018.

## Scope

- Версионировать first-run и activation contracts в signed umbrella manifest.
- Поддержать upgrade существующих OAuth/manual installs без повторного onboarding.
- Добавить feature flag, canary telemetry и rollback до старого flow.
- Зафиксировать deprecation старых values/Secret paths после migration window.

## Критерии приёмки

- Upgrade с существующей БД, projects, sessions и license не теряет состояние.
- Старый activation/license формат имеет явную migration/error policy.
- Rollback не делает созданные environment неуправляемыми.

