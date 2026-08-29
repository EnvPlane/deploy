# EP-SSO-018: Сделать clean-cluster E2E обязательным release gate

Зависит от: EP-SSO-002–017.

## Scope

- На пустом kind/minikube и поддерживаемом managed cluster выполнить anonymous Helm install.
- Через реальный browser пройти claim, current/remote cluster, SCM, first project/env,
  activation, expiry и free quota paths.
- Проверить reinstall, upgrade, rollback, interrupted wizard и cleanup.
- Сканировать cluster/Git/logs/artifacts на Secret leakage.

## Критерии приёмки

- Release не публикуется без Running first environment из clean cluster.
- Тест не использует ручные child chart builds или скрытые registry credentials.
- Failure сохраняет redacted evidence и автоматически удаляет disposable resources.

