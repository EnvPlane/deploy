# EP-SSO-001: Self-service installation, first-run onboarding and activation

## Product outcome

Любой пользователь с Kubernetes context и Helm устанавливает EnvPlane одной
командой без предварительного создания Secret. После первого открытия мастер
доводит установку до первого рабочего environment: настраивает текущий или
удалённый кластер, аутентификацию, репозитории, проект и GitOps. Код активации
расширяет базовые лимиты; без действующей лицензии продукт остаётся полезным и
разрешает один проект и два активных environment.

## Текущее состояние (2026-08-29)

- OCI umbrella chart существует, но production-документация требует GHCR pull
  access и operator values; same-cluster executors требуют отдельный pull Secret.
- Публичная landing-страница и единый public quick-start отсутствуют в workspace.
- Chart умеет генерировать внутренние PostgreSQL credentials и управляемые
  Agent/Runner registration materials, но zero-values install не является
  release-gated пользовательским контрактом.
- Authentication setup, project creation и Bootstrap реализованы отдельными
  экранами; общей resumable first-run state machine нет.
- Есть signed offline license API, verifier, plan catalog, entitlement resolver и
  quota gates. Нет activation-code issuer/redemption flow и Settings UI.
- Текущий `free` plan допускает 3 проекта и 2 environment; требуемый fallback —
  1 проект и 2 environment.

## Неподвижные продуктовые правила

1. Установка chart не требует OAuth, registry Secret, license или внешней БД.
2. Секреты вводятся только после запуска через write-only UI/API и никогда не
   возвращаются, не попадают в values, Git, telemetry или логи.
3. License enforcement выполняется server-side. UI только показывает решение.
4. Цена в activation payload является подписанным purchase/audit snapshot;
   права определяются plan/features/limits/expiry, а не ценой.
5. Expiry не удаляет ресурсы и не блокирует read, delete, cleanup, export или
   получение новой лицензии.
6. «Любой кластер» означает документированную support matrix, preflight и
   понятный fallback, а не скрытое изменение инфраструктуры пользователя.

## Порядок реализации

| Этап | Тикеты | Результат |
|---|---|---|
| Foundation | EP-SSO-001–004 | ADR, публичные artifacts и zero-secret Helm install |
| Discovery | EP-SSO-005–006 | landing quick-start и GitHub README |
| First run | EP-SSO-007–011 | resumable wizard до первого environment |
| Activation | EP-SSO-012–016 | signed activation, Settings UI и fallback limits |
| Release gate | EP-SSO-017–019 | observability, clean-cluster E2E и compatibility |

Каждый тикет выполняется отдельным reviewable commit/PR. Cross-repository
изменения координируются контрактом из `contracts`; следующий тикет не должен
реализовываться заранее.

