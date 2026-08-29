# EP-SSO-007: Ввести resumable first-run state machine

Зависит от: EP-SSO-003.

## Scope

- Добавить installation-scoped состояния: uninitialized, operator-claimed,
  cluster-ready, scm-ready, project-ready, environment-ready, complete.
- Сделать каждый transition idempotent, auditable и restart-safe.
- Защитить первый claim одноразовым локальным setup credential либо explicit
  local auto-claim policy; после claim anonymous mutation закрывается.
- Добавить safe progress API без Secret и персональных данных.

## Критерии приёмки

- Перезапуск Pod/browser продолжает wizard с последнего подтверждённого шага.
- Два оператора не могут одновременно присвоить installation.
- Reset требует явного подтверждения и не удаляет workloads автоматически.

