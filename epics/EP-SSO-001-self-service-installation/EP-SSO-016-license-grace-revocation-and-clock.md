# EP-SSO-016: Добавить production-safe lifecycle лицензии

Зависит от: EP-SSO-013, EP-SSO-015.

## Scope

- Добавить configurable grace, cached last-valid grant и monotonic last-seen time.
- Реализовать signed revocation list/online refresh с bounded timeout и offline fallback.
- Добавить verify-key rotation, activation replacement и disaster recovery.
- Аудировать изменения без code/signature leakage.

## Критерии приёмки

- Clock rollback не продлевает лицензию.
- Network outage не вызывает немедленный destructive downgrade.
- Revoked/expired state детерминированно переходит в free limits после grace.

