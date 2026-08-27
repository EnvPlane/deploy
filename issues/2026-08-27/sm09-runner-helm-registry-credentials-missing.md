# SM-09 Runner Helm registry credentials are missing

## Problem

The private-registry lifecycle harness provides `imagePullSecrets` to the
Runner, but Helm OCI resolution uses a separate registry configuration. The
authenticated Runner preflight therefore reports `helm_chart_auth_failed` for
the release workload chart even though Kubernetes can pull the Runner image.

## Required behavior

- Mount the disposable namespaced Docker configuration through
  `envplane-runner.helmRegistry.existingSecret`.
- Keep image-pull and Helm registry authentication explicit and separate.
- Never copy credential values into Helm values or CI output.
