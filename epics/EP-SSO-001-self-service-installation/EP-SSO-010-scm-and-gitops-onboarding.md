# EP-SSO-010: Подключить SCM и GitOps без повторного ввода credentials

Зависит от: EP-SSO-007.

## Scope

- Добавить GitHub/GitLab OAuth/PAT onboarding с раздельными app и GitOps repositories.
- Валидировать repositories, branches и write capability до сохранения.
- Persist только encrypted credential reference и safe validation proof.
- Не требовать повторного ввода неизменившегося токена; rotation остаётся явной.

## Критерии приёмки

- Wizard восстанавливает repository selection, но никогда plaintext credential.
- UI различает invalid, expired и insufficient-scope credentials.
- GitOps bootstrap идемпотентен и не перезаписывает чужие файлы.

