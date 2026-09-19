# EP-SSO-001: Зафиксировать self-service product contract и threat model

Зависит от: —.

## Scope

- Описать personas: anonymous landing visitor, cluster owner, first operator,
  tenant administrator и license issuer.
- Зафиксировать границы «one-command install», поддерживаемые Kubernetes/Helm,
  storage, ingress/Gateway и air-gapped варианты.
- Описать угрозы: supply-chain substitution, forged activation, replay,
  cross-tenant license, leaked SCM credentials, hostile chart values и clock rollback.
- Принять решение о hosted activation service и offline activation fallback.

## Критерии приёмки

- ADR содержит state diagram install → first run → activated/free/expired.
- Указаны owner-репозитории, API boundaries, rollback и migration policy.
- Нельзя трактовать anonymous install как anonymous Kubernetes mutation после install.

