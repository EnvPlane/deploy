# EP-SSO-014: Добавить activation UI в Settings

Зависит от: EP-SSO-012, EP-SSO-013.

## Scope

- Добавить поле activation code, Activate, Replace и Remove/return-to-free действия.
- Показывать plan, limits, features, price snapshot, issued/expiry, fingerprint и status.
- Никогда не возвращать полный activation code после submit.
- Добавить actionable states: invalid, wrong tenant, expired, revoked, clock invalid.

## Критерии приёмки

- Только `settings.write` может менять activation; `settings.read` видит safe metadata.
- Clipboard/DOM/logs/telemetry не содержат code после submit.
- UI немедленно обновляет quota guidance после успешной активации.

