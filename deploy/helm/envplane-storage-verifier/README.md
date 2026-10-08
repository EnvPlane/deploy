# Read-only local storage verifier

Disabled by default. This is a separate administrator installation, not a project
Agent/Runner resource. It observes node-local backend paths and never removes data.
See control-plane `docs/storage-provider-verification.md` for trust and coverage.

Required values: explicit hostPath approval, exact node/tenant/cluster generation,
an immutable image containing `/usr/local/bin/storage-verifier`, TLS Secret,
dedicated client CA Secret and provider signing Secret/key ID. Existing images
published before this executable was added cannot run this chart.

Secrets contain `tls.crt`/`tls.key`, client CA `ca.crt`, and signer `key` respectively.
Signer `key` is RawURL-base64 Ed25519 private key bytes, never a values string.
The provider signer is not an erasure authority. For completed erasure certificates,
optionally provide a separate certificate Secret and independent public-key
ConfigMap with `keys.json`. Each certificate filename is derived by
`storageverifier.CertificateFileName` and each certificate covers one exact volume.

The retained inventory PVC is independent of feature environments. Removing the
chart does not destroy that index. Its initializer writes only its private state
subdirectory. Host data roots are read-only `Directory` mounts: the chart never
creates, chmods or removes application paths. Mount/UID/namespace/node mismatches,
symlinks and missing pre-delete inventory remain UNKNOWN.

RBAC is metadata-read-only (PV/PVC/Namespace/StorageClass); no wildcard verbs,
Secret reads, node exec, filesystem deletion or workload mutations. The process
uses dropped capabilities, no privilege escalation and read-only root filesystem.
It runs as an administrator-controlled root UID solely to stat protected paths and
read root-owned keys, with only the private inventory volume writable.

Install only after reviewing this privileged read boundary. For multi-node storage,
use separately scoped node installations/endpoints; do not assume a node-local
observer certifies every node or a cloud CSI driver. A dedicated mTLS client CA
must authorize only management verifier clients, not arbitrary workload identities.

For a remote cluster, management must be able to reach the verifier endpoint.
`service.type` can explicitly select a TLS-preserving NodePort or LoadBalancer;
ClusterIP is the private default. Use a certificate matching the configured reachable
hostname/IP. Do not terminate mTLS at an unauthenticated HTTP proxy or publish this
service implicitly during project onboarding.

HostPath deletion is logical backend-object absence, not secure erase. Existing
unencrypted data cannot become erased by relabelling it. Backups/snapshots and
forensic sanitization require separate authority/evidence and remain UNKNOWN.
