# AI provider configuration

AI is disabled by default. Enabling it does not create an API endpoint or grant
the provider access to Agents, Runners, Kubernetes, or control-plane actions.
The control plane sends only the bounded, redacted context produced by the
versioned AI context builder.

Configure the OpenAI adapter with a Kubernetes Secret reference. Do not put a
key in Helm values, Git, logs, or API responses:

```yaml
commercialization:
  ai:
    enabled: true
    provider: openai
    model: gpt-5.4
    apiKeySecretRef:
      name: envplane-ai-provider
      key: api-key
    maxContextBytes: 65536
    maxOutputTokens: 512
    timeoutSeconds: 10
    maxRetries: 2
```

The model must be present in the server-side allowlist. The adapter uses the
Responses API with `store: false`, strict Structured Outputs JSON Schema, a
deadline, cancellation, and bounded retries only for rate-limit, timeout, and
provider-unavailable responses. Authentication and schema failures are not
retried. A provider outage is returned as a classified provider error and does
not affect ordinary EnvPlane endpoints or reconcilers.

Provider routing is deterministic and fail-closed. A route must match the tenant
provider mode, explicitly allowed region, model allowlist, required capability,
prompt/schema pins, and the server-side eval-gate version. Fallback is bounded by
`commercialization.ai.routing.maxFallbacks` and can only select another provider
with the same mode and region; it never crosses external/self-hosted or residency
boundaries. Leave `requiredEvalGateVersion` and `schemaVersionPin` empty until the
corresponding eval gate has approved the model change.

## Air-gapped installations

Set `commercialization.ai.airGap=true` and configure tenant policy mode `offline`
to use a locally mounted `commercialization.ai.offlineModelBundle` path. The
control plane disables external and self-hosted HTTP providers before resolving
tenant policy, so air-gap mode performs no provider DNS, HTTP, or secret lookup.
The bundle is a versioned local artifact and must already be covered by the
signed air-gap manifest; the Helm value is a path, never model or secret bytes.
Without a valid bundle the server remains available and returns the typed
insufficient-evidence fallback. Keep `airGap=true` for offline verification and
do not use the external provider mode in an air-gapped cluster.

Generated analysis runs use a separate opt-in sandbox contract. The sandbox image
must be pinned by digest, inputs are signed references, network access is denied by
default, and only exact configured egress destinations may be allowed. Sandbox
limits enforce non-root execution, RuntimeDefault seccomp, no privilege
escalation, bounded PIDs, timeout and output size. Provider, SCM, Kubernetes and
Runner credentials are never mounted into the sandbox.
