# External platform capability contract

`platformDependencies.ingress`, `.dns` and `.storage` describe capabilities
owned by the cluster platform, not by EnvPlane workloads. Every entry uses one
of four modes:

| Mode | Ownership and behavior |
| --- | --- |
| `auto` | Detect a healthy compatible capability and reference it without Helm adoption. If none is detected, install only the explicitly named `provider`; missing provider configuration is a values error. |
| `managed` | EnvPlane's configured reconciler owns the explicitly named provider. `provider`, version and any provider credentials are required. |
| `existing` | Reference an already installed capability (`existingClassName` or `existingSecret`). EnvPlane never adopts, upgrades or deletes it. |
| `disabled` | No capability is required or configured. |

The typed status values are `detected`, `managed`, `missing`, `incompatible`,
`degraded` and `disabled`. The chart publishes the selected mode, provider,
ownership, namespace, version, reference and credential Secret name in the
`<release>-platform-dependency-status` ConfigMap. Secret values are never
rendered; only the Secret name is exposed.

`auto` and `managed` require an explicit provider. `existing` requires a
reference. These checks happen during Helm rendering so an incomplete values
file fails with an actionable message. A provider reconciler may create only
resources it owns, must preserve existing resources during upgrades, and must
not uninstall an external capability. `managed` resources are upgraded only
within the configured provider/version contract and are removed on uninstall
only when the provider's ownership policy explicitly permits it.

The control plane consumes the same fields through its capabilities contract,
including ownership and compatibility metadata, allowing the UI to distinguish
missing or degraded platform capabilities from an intentionally disabled one.
