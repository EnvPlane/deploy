# SM-09 compiles without a Runner-validated chart contract

## Problem

The private-registry lifecycle harness advances Bootstrap to final review with
only Secret strategies. If the chart-managed fixture reconciler has not yet
persisted its deployment block, compilation succeeds without a Helm chart
reference. Environment creation then fails with
`helm_chart_reference_invalid`.

## Required behavior

- Persist the complete Helm Direct deployment contract before compilation.
- Exercise the authenticated Runner chart preflight endpoint.
- Wait for the matching chart reference and version to be confirmed by the
  Runner before compiling the project configuration.
- Keep the preflight failure diagnostic redacted.
