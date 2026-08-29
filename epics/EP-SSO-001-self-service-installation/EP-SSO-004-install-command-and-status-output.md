# EP-SSO-004: Создать каноническую install-команду и post-install handoff

Зависит от: EP-SSO-003.

## Scope

- Зафиксировать stable OCI coordinate и version-selection policy без `latest`.
- Добавить Helm NOTES с URL/port-forward, readiness command и first-run URL.
- Добавить idempotent preflight helper, который только диагностирует cluster и
  формирует values override; он не читает и не печатает credentials.
- Нормализовать install/upgrade/uninstall и recovery команды.

## Критерии приёмки

- Пользователь копирует одну команду и получает URL следующего шага.
- Ошибки RBAC/storage/network содержат проверку и исправление.
- Команда одинакова на landing и в README и проверяется CI snapshot test.

