# EP-SSO-017: Добавить first-run observability и support bundle

Зависит от: EP-SSO-007–016.

## Scope

- Ввести step-level metrics, bounded failure categories и correlation ID.
- Добавить downloadable redacted support bundle с versions, readiness и safe events.
- Собирать opt-in product funnel без repository names, tokens или resource manifests.
- Добавить UI retry/resume и ссылку на конкретную remediation.

## Критерии приёмки

- Support bundle проходит secret scanner.
- Можно измерить install → first environment conversion и время каждого шага.
- Диагностика работает в offline режиме.

