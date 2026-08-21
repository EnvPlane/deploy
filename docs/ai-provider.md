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
