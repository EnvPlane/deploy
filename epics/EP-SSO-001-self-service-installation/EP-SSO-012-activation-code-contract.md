# EP-SSO-012: Спроектировать подписанный activation-code contract

Зависит от: EP-SSO-001.

## Scope

- Расширить versioned license grant installation/tenant binding, SKU, plan/version,
  features, limits, issue/not-before/expiry, license ID и nonce.
- Добавить signed commercial snapshot: currency, amount, billing interval и tax mode.
- Использовать Ed25519/ECDSA key IDs; private signing keys находятся только в issuer.
- Определить compact transport encoding, максимальный размер и offline verification.

## Критерии приёмки

- Tamper, wrong installation/tenant, replay, unknown key и expiry отклоняются.
- Цена не участвует в authorization decision.
- Canonical schema и test vectors опубликованы в `contracts`.

