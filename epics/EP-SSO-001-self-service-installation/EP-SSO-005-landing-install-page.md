# EP-SSO-005: Создать первую страницу landing с guided install

Зависит от: EP-SSO-004.

## Scope

- Создать публичную страницу `/install` в отдельном website/landing owner-repo.
- Показывать prerequisites, support matrix, выбранную stable версию, copyable Helm
  command, проверку статуса и ожидаемый first-run экран.
- Добавить переключатели current/remote cluster и cloud/on-prem без запроса Secret.
- Не собирать kubeconfig, cluster credentials или SCM tokens на landing.

## Критерии приёмки

- Новый пользователь понимает путь менее чем за минуту и начинает install без регистрации.
- Команды формируются только из подписанного release index.
- Mobile/accessibility/analytics/privacy проверки входят в release gate.

