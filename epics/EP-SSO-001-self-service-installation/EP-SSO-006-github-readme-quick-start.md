# EP-SSO-006: Переработать GitHub README и installation docs

Зависит от: EP-SSO-004, EP-SSO-005.

## Scope

- Разместить quick start в первых экранах README основного install-репозитория.
- Описать install, first-run, free limits, activation, upgrade и uninstall.
- Вынести production hardening, private registry и external DB в advanced раздел.
- Добавить troubleshooting matrix и ссылку на versioned docs конкретного release.

## Критерии приёмки

- Quick start не требует Secret или ручной сборки child charts.
- README и landing используют один машинно-проверяемый command source.
- Документация не обещает автоматическую установку неподдерживаемых cluster add-ons.

