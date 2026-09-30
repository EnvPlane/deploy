# Runtime credential persistence

Agent and Runner exchange a one-time registration credential for a durable
runtime credential. The runtime credential must survive an ordinary pod
restart; removing persistence is not a cost optimization if it causes replay
of the consumed registration token.

Each child chart supports mutually exclusive modes under `authPersistence`:

| Mode | Storage dependency | Restart recovery | Use case |
| --- | --- | --- | --- |
| `managed` | One chart-managed PVC per runtime | Durable file | Default, isolated project identity |
| `externalSecret` | Kubernetes Secret only | Secret-backed token | Secret operator or pre-provisioned Secret |
| `externalPVC` | Existing PVC only | Durable file | Platform-managed storage lifecycle |

Leave `mode` empty to infer the legacy fields (`existingSecret`, then
`existingClaim`, otherwise managed PVC). A configuration that supplies both
references, or a reference incompatible with an explicit mode, fails Helm
rendering. The old `createClaim: false` path remains an explicit `ephemeral`
compatibility mode; it is not restart-durable and is not recommended for
production.

The default pair therefore provisions two small claims per project runtime
pair. Actual cloud cost is provider and StorageClass specific: the billable
minimum can exceed the requested `1Mi`, and provision latency is added to pod
startup. `externalSecret` removes both PVC provisioning and the StorageClass
requirement, but shifts durability, rotation, and recovery guarantees to the
Secret manager. `externalPVC` keeps those guarantees while allowing a platform
to share a storage lifecycle; it does not merge Agent and Runner identities.

No automatic mode selection is performed from cloud detection. Operators must
choose a mode whose durability and startup guarantees are understood.
