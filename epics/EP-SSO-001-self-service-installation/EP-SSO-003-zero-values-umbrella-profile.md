# EP-SSO-003: Добавить безопасный zero-values профиль umbrella chart

Зависит от: EP-SSO-002.

## Scope

- Определить defaults для API/frontend, internal PostgreSQL/Redis, persistence,
  current-cluster Agent/Runner и managed registration.
- Не требовать заранее созданных Secret; генерировать только Kubernetes-managed
  credentials с upgrade-safe ownership.
- Реализовать access fallback: Ingress/Gateway при обнаружении capability либо
  явная инструкция port-forward, без молчаливой установки cluster add-ons.
- Добавить pre-install validation и actionable ошибки для StorageClass/RBAC.

## Критерии приёмки

- Одна Helm-команда без values и `--set` даёт Ready release на support-matrix cluster.
- Повторный install/upgrade не меняет credentials и не теряет данные.
- `helm template`, lint и policy tests доказывают отсутствие plaintext Secret.

