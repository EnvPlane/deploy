# EP-SSO-013: Реализовать activation issuer и redemption lifecycle

Зависит от: EP-SSO-012.

## Scope

- Создать hosted endpoint landing → checkout/request → activation code.
- Поддержать online redemption и offline copy/paste без передачи cluster credentials.
- Добавить idempotency, revocation, replacement, key rotation и audit events.
- Не помещать issuer private key в open-source runtime или chart.

## Критерии приёмки

- Один purchase безопасно повторно выдаёт тот же grant либо контролируемую replacement revision.
- Replay на другую installation/tenant блокируется.
- Outage issuer не ломает уже установленную действующую лицензию.

