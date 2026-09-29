# Аудит лишней настройки и ресурсов envplane

Дата: 2026-09-29. Проверены локальные HEAD: control-plane bdeed52, deploy 63d86e1, frontend 0c586c1, agent d937feb, runner 634c341, webhook 25632b8, gitops 6bae5a6, bootstrap 18535a8, contracts 0745bfe, activation-issuer a4b9f5e.

## Результат

17 отдельных пунктов: 16 дефектов/несогласованностей, подтвержденных исходным кодом или локальным рендерингом, и 1 архитектурное предложение (AUD-014). Это аудит путей настройки, создания, обновления и удаления ресурсов, а не утверждение о полном покрытии каждой функции и каждого live-сценария.

Предыдущая оценка последнего RBAC-фикса была слишком оптимистичной: широкая делегация, коллизии имен, отсутствие namespace metadata доступа и неполная упаковка делают его непригодным к принятию как завершенного исправления. До следующего rollout необходимы AUD-001—006 и проверка обновления существующей установки.

## Реестр

| Тикет | Приоритет | Объём | Проблема |
|---|---|---|---|
| [AUD-001](AUD-001-rbac-global-delegation.md) | P1 | Security design + integration tests; L | Cluster-scoped binding can bypass intended namespace boundary |
| [AUD-002](AUD-002-capability-binding-name-collision.md) | P1 | S | Two fixed capability bindings render with the same Kubernetes identity |
| [AUD-003](AUD-003-namespace-metadata-access.md) | P1 | M | Project Agent loses access to Namespace metadata |
| [AUD-004](AUD-004-discovery-write-permissions.md) | P1 | M | Discovery namespace selection grants workload and Secret mutations |
| [AUD-005](AUD-005-profile-reconciliation-parity.md) | P1 | M | New profile lacks discovery-parent bindings and identity parity |
| [AUD-006](AUD-006-chart-version-migration.md) | P1 | M | Fixed-role code requires coordinated chart publication and migration |
| [AUD-007](AUD-007-renderer-duplicates.md) | P2 | S | Repeated namespaces render duplicate resources |
| [AUD-008](AUD-008-helm-direct-gitops.md) | P2 | M | Connected Helm Direct requires an unnecessary writable GitOps repository |
| [AUD-009](AUD-009-unchanged-components-proof-reset.md) | P2 | S | Saving unchanged components invalidates all SCM proofs |
| [AUD-010](AUD-010-optional-ingress-ui.md) | P2 | M | Wizard requires IngressClass for workloads without ingress |
| [AUD-011](AUD-011-auth-pvc-retention.md) | P1 | M | Auth PVC preservation is documented but absent from chart lifecycle |
| [AUD-012](AUD-012-cleanup-secret-ownership.md) | P2 | S | Same-cluster project cleanup deletes bootstrap Secret by name only |
| [AUD-013](AUD-013-noop-helm-upgrades.md) | P2 | M | Unchanged executor reconciliation can create redundant Helm revisions |
| [AUD-014](AUD-014-credential-pvc-footprint.md) | P3 | L | Offer a supported durable credential mode without one PVC per runtime |
| [AUD-015](AUD-015-issuer-preinstall-serviceaccount.md) | P1 | S | Issuer migration pre-install hook requires an account created after the hook |
| [AUD-016](AUD-016-issuer-migration-pull-secrets.md) | P2 | S | Issuer migration Job ignores imagePullSecrets |
| [AUD-017](AUD-017-ci-vendoring-drift-order.md) | P2 | S | CI rebuilds dependencies before checking committed vendoring |

Объем: S — локальное исправление; M — несколько связанных компонентов/сценариев; L — архитектурное изменение с миграцией. Это относительные оценки, не обещание срока.

## Что воспроизведено локально

- Renderer: повторение `--managed-namespace base-api` создаёт два Role и два RoleBinding с одинаковой идентичностью.
- Helm: два fixed capability roles для `customer-west` и release `remote-agent` дают одинаковое имя `remote-agent-envplane-agent-envplane-remote-cluster-customer-we` и различные roleRef.
- `bash scripts/check-vendored-chart-drift.sh` в deploy завершается с кодом 1: `vendored chart drift detected: envplane-agent-0.2.29.tgz`.
- Issuer chart render: pre-install Job использует обычный chart ServiceAccount; imagePullSecrets присутствуют только в Deployment.
- Остальные выводы — сопоставление исходного кода, chart правил, условий UI и cleanup/reconcile путей. Кластерная эскалация прав и разрушительная очистка не выполнялись; это анализ явно выдаваемых прав и кода.

## Охват

| Направление | Проверено |
|---|---|
| frontend / control-plane | мастер bootstrap, SCM proofs, backend-зависимые требования, ingress gate, профиль удаленного кластера |
| deploy | Agent/Runner RBAC, auth PVC, генератор подключения, child/umbrella packaging, порядок CI |
| control-plane / agent / runner | namespace discovery, identity persistence, создание parent bindings, повторный reconcile и cleanup |
| bootstrap / gitops / webhook / contracts | роль модулей в настройке, SCM/GitOps зависимости, runtime контракт и границы credentials; отдельный построчный аудит всего кода этих модулей не выполнялся |
| activation-issuer | чистая установка chart, миграции, ServiceAccount, private registry конфигурация |

## Порядок реализации

1. Исправить RBAC-контракт целиком (AUD-001—006): модель делегации, уникальность имен, metadata, readonly discovery, identity parity, версия/миграция. Не расширять доступ для обхода отсутствующего разрешения.
2. Устранить блокеры чистой установки issuer и CI (AUD-015—017), а также дубли renderer (AUD-007).
3. Упростить пользовательский мастер (AUD-008—010): backend сначала, только необходимые SCM/Ingress настройки, сохранение неизменённых доказательств доступа.
4. Сделать lifecycle идемпотентным и безопасным (AUD-011—013): retain/purge, проверка владельца и UID, no-op reconcile.
5. Оценить модель durable credentials (AUD-014) с замерами и миграцией. Два auth-PVC на пару Agent/Runner можно оптимизировать только после сохранения гарантий восстановления.

## Что не следует автоматически удалять

- Раздельные Agent/Runner и идентичности проектов обеспечивают изоляцию; объединять их только ради меньшего числа Pod нельзя без отдельной модели безопасности.
- PostgreSQL и защищенный signer issuer имеют самостоятельное назначение; отсутствие встроенного production signer/БД в chart само по себе не дефект.
- Durable credential state необходим после одноразового bootstrap. Переход на emptyDir без восстановления создаст повторные проблемы авторизации.
- Публичный HTTPS endpoint нужен внешнему GitLab/GitHub для доставки webhook; временный tunnel — тестовая инфраструктура, не обязательный элемент production продукта.

## Граница выполненного

Созданы тикеты с доказательствами, требованиями приемки и промптами для Codex. Изменений runtime-кода, прав Kubernetes, ресурсов и релизов в этом аудите нет. Документы сохранены в Git отдельным локальным коммитом; публикация и реализация этих новых тикетов в данную проверку не входят.
