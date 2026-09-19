# EP-SSO-015: Зафиксировать режим без лицензии — 1 project и 2 environment

Зависит от: EP-SSO-012.

## Scope

- Изменить canonical free plan: `projects.max=1`, `environments.active.max=2` и aliases.
- Применять fallback при missing, invalid, revoked и окончательно expired activation.
- Сохранить read/delete/cleanup/export; блокировать только новые превышающие mutations.
- Определить поведение существующих ресурсов сверх лимита без автоматического удаления.

## Критерии приёмки

- Backend quota gates являются authoritative и race-safe.
- Третий environment и второй project получают typed 429 с upgrade guidance.
- Expiry не останавливает существующие workloads и не препятствует cleanup.

