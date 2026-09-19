# EP-SSO-011: Автоматизировать первый project и environment

Зависит от: EP-SSO-008 или EP-SSO-009; также EP-SSO-010.

## Scope

- Собрать project, components, namespaces, materialization strategies и GitOps config
  в один review step.
- Создать project, дождаться deploy-ready Agent/Runner, выполнить resource scan и compile.
- Создать первый environment и показать workload/readiness/URL.
- Реализовать compensation: частичный failure не оставляет скрытый active quota usage.

## Критерии приёмки

- Clean install до первого Running environment проходит одним wizard.
- Retry не создаёт дубликаты project/environment/Git commits.
- Все ошибки сохраняют evidence и не раскрывают Secret.

