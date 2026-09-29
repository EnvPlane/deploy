# AUD-010: Wizard requires IngressClass for workloads without ingress

Status: confirmed by source audit; not fixed.
Priority: P2
Estimated effort: M

## Evidence

frontend/components/bootstrap/BootstrapWizardClient.tsx:1882-1883,4723; control-plane/internal/server/current_cluster_preflight.go:91-92

UI cluster gate requires nonempty ingress class while API preflight calls missing ingress optional. A typed name alone does not install a controller.

## Implementation prompt for Codex

Add a no-ingress route mode. Require and validate IngressClass only when generated resources or the selected chart need it. Test ClusterIP-only and ingress-enabled projects, retaining route-readiness failures where needed.

Commit verified iterations with English messages. Distinguish local tests from live acceptance.
