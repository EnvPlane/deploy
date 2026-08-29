# EP-SSO-009: Встроить подключение удалённого кластера в first run

Зависит от: EP-SSO-007.

## Scope

- Переиспользовать API-managed RemoteCluster flow в wizard.
- Принимать kubeconfig/credential только write-only или через existing Secret reference.
- Проверять HTTPS management endpoint, CA distribution, namespace allowlist и heartbeat.
- Разрешать продолжить только после fresh authenticated Agent/Runner readiness.

## Критерии приёмки

- В браузерных read models отсутствуют kubeconfig/token/certificate bytes.
- Ошибка связи оставляет wizard resumable и даёт точную remediation.
- Current и remote cluster используют единый target contract.

