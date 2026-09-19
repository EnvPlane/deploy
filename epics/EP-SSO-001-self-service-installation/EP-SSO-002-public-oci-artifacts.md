# EP-SSO-002: Сделать install-critical OCI artifacts доступными без registry Secret

Зависит от: EP-SSO-001.

## Scope

- Опубликовать umbrella chart и все обязательные runtime images/charts с anonymous pull.
- Устранить зависимость clean install от `envplane-ghcr` в management и executor namespaces.
- Сохранить private registry support как явный optional override.
- Добавить CI-проверку anonymous pull по digest для amd64/arm64 и Helm pull без login.

## Критерии приёмки

- На чистой машине `helm pull` и Kubernetes image pulls проходят без credentials.
- Release manifest содержит immutable digest каждого artifact и SBOM/provenance.
- Закрытый artifact не может попасть в public umbrella release.

