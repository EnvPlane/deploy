# EP-SSO-008: Автоматизировать настройку текущего кластера

Зависит от: EP-SSO-007.

## Scope

- Обнаруживать cluster identity, ingress classes, storage classes и доступные namespaces.
- Предлагать безопасный project-owned base namespace и executor namespace.
- Reconcile Agent/Runner из текущего signed compatibility manifest.
- Показать preflight и remediation для недостающих RBAC/storage/network capabilities.

## Критерии приёмки

- Default путь не требует ручной установки Agent/Runner.
- Все созданные ресурсы имеют ownership labels и безопасно восстанавливаются.
- Никакой cluster-wide capability не устанавливается без явного согласия.

