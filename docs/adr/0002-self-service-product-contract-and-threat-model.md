# ADR-0002: Self-service product contract, activation and threat model

**Status:** Accepted  
**Date:** 2026-08-29  
**Deciders:** EnvPlane maintainers  
**Depends on:** ADR-0001

## Context

EnvPlane is distributed as a public OCI Helm umbrella but operates a control
plane that can manage user-provided clusters, source-control credentials and
licensed tenant capacity. The product needs an unambiguous boundary between a
visitor who obtains a public artifact and an authenticated operator who changes
a running installation. It also needs licensing that works for connected and
air-gapped customers without putting issuer secrets into the chart or runtime.

This ADR is the product contract for EP-SSO-001. Detailed schemas and UX follow
in the dependent EP-SSO tickets.

## Decision

### Personas and authority

| Persona | May do | Must not be able to do |
|---|---|---|
| Anonymous landing visitor | Read public docs, artifact digests, support matrix and install command; anonymously pull public release artifacts. | Read installation state, claim an installation, mutate Kubernetes after Helm exits, submit SCM credentials or redeem a license. |
| Cluster owner | Select an existing kubeconfig context, execute the documented Helm command, select reviewed non-secret values, and own platform prerequisites and upgrades. | Delegate cluster-admin access to the application, inject plaintext credentials through values, or expect EnvPlane to provision a cluster, DNS zone, cloud account or tunnel. |
| First operator | Present the one-time local setup credential (or use an explicitly enabled local auto-claim policy), claim the installation, establish the first tenant and configure first-run steps. | Reclaim an already claimed installation anonymously or retrieve the setup credential after it is consumed. |
| Tenant administrator | Use authenticated, tenant-scoped APIs/UI to manage users, SCM references, projects, environments, remote clusters and activation subject to permissions. | Read another tenant's data, Secret values, issuer private keys or raw kubeconfig/SCM credentials. |
| License issuer | Issue, replace, revoke and audit signed grants through the hosted issuer service under separation of duties. | Access customer clusters, authenticate to their SCM, or place a signing key in public artifacts, charts or control-plane runtime. |

The cluster owner and first operator can be the same person, but their authority
is deliberately distinct. A Helm install authenticates only to the customer's
Kubernetes API. It establishes a local installation and a one-time claim path;
it does **not** establish an anonymous EnvPlane operator. Once the claim
succeeds, every mutating application API requires an authenticated principal
and tenant/installation authorization. Anonymous endpoints are limited to
liveness/readiness, public static assets and the claim bootstrap exchange; none
accept a general Kubernetes mutation request.

### One-command installation boundary and support matrix

The supported command is the one in `docs/installation.md`: a Helm 3.14+
`upgrade --install` of a versioned, public OCI `envplane` umbrella release into
a customer-selected namespace on Kubernetes 1.26+. “One command” means the
chart installs EnvPlane's default API/frontend path without a license, OAuth
client, registry credential, external database or pre-created EnvPlane Secret.
It does not mean EnvPlane silently changes customer infrastructure after
installation.

| Area | Supported contract | Explicit boundary/fallback |
|---|---|---|
| Kubernetes and Helm | A pre-existing Kubernetes 1.26+ cluster and Helm 3.14+; the caller has permissions only for the selected namespace and enabled features. | No cluster, node-pool, cloud-account, IAM, tunnel or DNS-zone provisioning. Unsupported distributions fail preflight with a diagnostic. |
| Storage | A default StorageClass, or explicitly selected compatible existing/managed provisioner, for enabled persistence. | `platformDependencies.storage.mode=disabled` is valid only when persistence-dependent components are disabled or use external services. No guessed cloud CSI configuration. |
| Ingress / Gateway | A healthy existing Ingress controller or Gateway API implementation, or an explicitly pinned managed provider as defined by ADR-0001. Gateway certificate attachment and DNS are platform-owned. | `access.mode=disabled` supports cluster-local/operator access; no automatic public endpoint, certificate, Gateway, DNS record or cloud load balancer. |
| Images and registry | Public OCI artifacts are anonymously pullable. Private mirrors use immutable, signed EnvPlane releases and existing image-pull Secret references. | Mutable tags and unverified image/chart overrides are rejected; a registry Secret is never plaintext values. |
| Air-gapped | Import the complete digest-pinned release bundle and approved verify-key/revocation bundle into an internal registry, then install from it with explicit values. Offline grant copy/paste is supported. | No network discovery, hosted activation, SCM OAuth callback, telemetry upload or automatic key/revocation refresh is assumed. Refresh the bundle before its declared validity horizon. |

The install may create only resources owned by the selected Helm release and its
explicitly enabled documented dependencies. Any platform reconciler is bounded
by ADR-0001: it manages only an explicitly configured pinned provider and never
adopts unrelated resources. Remote cluster work begins only after an
authenticated tenant administrator creates desired state that references an
operator-provisioned Secret; it is not a side effect of anonymous installation.

### Installation and entitlement state machine

The control plane persists installation state, transition generation, timestamps
and audit actor. Transitions are idempotent; retries return current safe state
and never return a setup credential, activation code or Secret. `expired`
includes a revoked grant after its configured grace period. `free` is the useful
fallback plan: one project and two active environments.

```text
                         Helm release succeeds
 [not-installed] --------------------------------> [uninitialized]
                                                        |
                         one-time setup credential      | explicit local auto-claim
                              + authenticated actor     | (operator policy only)
                                                        v
                                                [operator-claimed]
                                                        |
                                          resumable first-run transitions
                                                        v
 [first-run incomplete] <---------------------- [first-run]
            | cluster/scm/project/environment steps       |
            +---------------------------------------------+
                                                        |
                                                        v
                                                  [operational]
                                                   /     |      \
                                    no valid grant /      |valid  \ grant expiry,
                                                 v       |       \ revocation + grace
                                             [free] <----+----> [activated] ----> [expired]
                                               ^             replace/redeem grant    |
                                               |                                      |
                                               +----------- valid replacement --------+
```

First-run progress is independent of entitlement: an installation may become
operational in `free`, and an activated installation may retain incomplete
optional onboarding. A grant is accepted only if its signature, key ID, format
version, installation ID, tenant ID, nonce and time window validate.
`activated` is an entitlement state, not an authorization bypass. Removal or
expiry changes only entitlement gates; it never deletes resources or blocks
read, delete, cleanup, export or acquisition of a replacement grant.

### Hosted activation with offline fallback

We will operate a hosted activation service for purchase/request, redemption,
replacement, revocation distribution and issuer audit. It receives the minimum
installation/tenant public identifiers necessary for redemption; it never
receives kubeconfig, SCM credentials, chart values, workload logs or inventory.

The issuer signs versioned grants using Ed25519 or ECDSA keys identified by
`kid`. Private keys remain in issuer-controlled key management; deployed
runtimes contain only pinned public verification keys and signed key-rotation
material. Online redemption is idempotent for a purchase and grant revision.
The control plane verifies the returned signed grant locally before persisting
safe metadata and a protected grant envelope.

Offline activation is an equal authorization path, not a weaker local override:
the customer transfers a compact signed grant through authenticated Settings or
a controlled import procedure. The same local verifier enforces binding, nonce,
replay and expiry checks. Air-gapped installations receive issuer public keys
and signed revocation data through a separately verified offline bundle. Issuer
unavailability must not invalidate a previously valid grant; stale revocation
or key data is surfaced and follows the bounded grace policy in EP-SSO-016.

### API and repository ownership boundaries

| Concern | Owner repository/service | Boundary |
|---|---|---|
| Public install docs, umbrella chart, signed compatibility manifest and release provenance | `deploy` | OCI/Helm artifact contract, non-secret values schema and support-matrix publication. |
| Installation claim, first-run state, authorization, tenant isolation, entitlement verification and quota enforcement | `control-plane` | Authenticated application API; emits safe progress and audit records only. |
| First-run and Settings UI | `frontend` | Consumes safe authenticated APIs; never decides authorization or retains a submitted Secret/activation code. |
| Remote execution reconciliation | `agent`, `runner`, `control-plane` | Desired state is tenant-authorized; reconciler reads referenced Secret material and applies exact compatible artifacts. |
| Activation schema, signatures, verification vectors and compatibility versions | `contracts` | Language-neutral signed contract; changed format requires a new version and test vectors. |
| Purchase, signing, redemption, replacement, revocation and issuer audit | Hosted issuer service (private) | Minimal TLS API; no issuer private key or admin endpoint ships in product repositories. |

The chart never calls the issuer. The frontend never calls issuer administration
APIs directly. The hosted service has no Kubernetes or customer SCM access. All
cross-boundary requests carry an explicit contract version and are authenticated
and authorized at the receiving boundary.

### Threat model and required controls

| Threat | Required controls | Detection / recovery |
|---|---|---|
| Supply-chain substitution | Signed release provenance and compatibility manifest; pinned chart versions and image digests; verified public/mirror artifacts; least-privilege short-lived release credentials. | Pre-install/upgrade validation rejects unpinned or mismatched artifacts. Revoke affected keys/artifacts and publish a signed replacement. |
| Forged activation | Canonical versioned payload, issuer-held private keys, `kid`-selected public keys and local signature verification. Price is audit data, never authorization input. | Reject unknown key, malformed payload or signature; audit a safe reason. Rotate keys and replace grants. |
| Replay | Bind grant to installation ID and tenant ID; immutable license ID, nonce and monotonic grant revision; idempotent redemption but reject nonce already consumed by a different binding. | Persist replay metadata transactionally; provide issuer replacement/recovery. |
| Cross-tenant license | Server-side tenant/installation check for every entitlement decision; tenant-scoped license APIs. | Reject mismatch before persistence; audit actor, tenant and safe license fingerprint. |
| Leaked SCM credentials | Write-only Secret APIs; secret-manager/Kubernetes references rather than values; least-privilege SCM tokens; redaction in logs, events and support bundles; no credential telemetry. | Rotate/revoke and safely re-test connection; never echo credential diagnostics. |
| Hostile chart values | Values schema, allowlisted coordinates from signed manifest, existing-Secret references only, least-privilege RBAC and policy tests rejecting unsafe development escapes. | Helm preflight rejects invalid/conflicting values before mutation; reviewed operator values and explicit rollback. |
| Clock rollback | Persist monotonic `lastSeenAt`; effective time is later of trusted current time and persisted time; signed issue/not-before/expiry and bounded grace. | A backward clock cannot extend a grant. Emit clock anomaly audit; time correction or replacement restores evaluation. |

Cluster-owner credentials and tenant-administrator sessions remain explicit trust
anchors; they are never anonymous inputs.

### Upgrade, rollback and migration policy

1. Every umbrella release pins a compatibility set, including first-run and
   activation-contract versions. Upgrades use the documented reset-values
   wrapper and a durable reviewed operator-values file, not `--reuse-values`.
2. `control-plane` migrations must be additive and backward compatible across
   the documented N-1 to N rollback window. A destructive, irreversible or
   entitlement-rewriting migration requires a separate versioned job, backup,
   operator runbook and explicit approval; it cannot silently ship in a patch
   chart release.
3. Helm rollback restores the prior signed compatibility set. It does not delete
   tenant data, environments, grants, audit records, existing platform
   dependencies or externally managed Secrets. A shared provider is not
   automatically downgraded.
4. First-run migrations retain last confirmed state and generation; an
   unsupported future state fails closed for mutation with a recovery diagnostic,
   not a reset to anonymous. Existing OAuth/manual installs map to an
   authenticated claimed state and are never forced through a new claim.
5. License readers support the current and preceding documented format during
   the migration window. Unsupported, invalid or unbound grants fall back to
   `free` after grace and preserve safe diagnostic metadata for replacement. A
   rollback never transforms a new grant into an unbound grant.

## Consequences

- Public installation remains low-friction while post-installation mutation is
  always attributable to an authenticated principal.
- Connected customers get a supportable activation/revocation lifecycle;
  isolated customers retain a verifiable, auditable offline path.
- Implementation remains split across dependent EP-SSO tickets; all preserve
  this ADR's invariants.
- Operators explicitly manage air-gap artifact/key/revocation bundle refresh
  and platform prerequisites.

## References

- [ADR-0001: Real Helm umbrella chart](0001-real-umbrella-chart.md)
- [Installation contract](../installation.md)
- [Chart ownership and migration](../helm-chart-ownership.md)
- [EP-SSO-001 epic](../../epics/EP-SSO-001-self-service-installation/README.md)
