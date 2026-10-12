# Readiness fixes after umbrella 0.4.721

This iteration prepares source fixes; it does not update the installed umbrella.

## Source changes

- frontend: retain tenant on ordinary capability 403; gate configured
  authentication/management endpoint writes by active owner/admin membership;
  preserve initial operator setup separately.
- frontend: pure observed billing activation clock, expiration checked again
  at submission, billing refresh effect dependencies corrected.
- control-plane: published contracts v0.1.115 replaces v0.1.113; exact remote tag,
  module checksums and reviewed schema snapshot regenerated without replace.
- control-plane: minute-scheduled bounded fair audit catch-up instead of a single
  daily batch; cancellation/error isolation and legal holds unchanged.
- control-plane: typed, sanitized Bootstrap fallback explains known blockers;
  pending source approval must match the current server review and tenant.
- agent: bounded terminal auth retry and no scan dispatch after rejected heartbeat.

## Verification boundaries

- control-plane: complete `go test -race ./...` PASS; focused snapshot/AI repeat PASS;
  `golangci-lint` with Go 1.26.9 PASS (zero issues).
- agent: complete `go test -race ./...` PASS.
- frontend: 567 unit tests PASS; lint and typecheck PASS. Expiration-at-submit
  regression added after the first full suite and repeated before publication.
- contracts: exact published v0.1.115 metadata and canonical served schema match.

Local Go race tests and unit checks are independent from hosted CI and deployed
acceptance. No live audit purge, credential rotation, source grant, promotion,
payment, Agent retirement or umbrella deployment was used as a test shortcut.

## Remaining production gates

Fresh installed UI/lifecycle/PVC-copy acceptance; independent owner source approval;
fresh CNI evidence; priced nonempty FinOps telemetry; production issuer/keys and
full management-plane DR; operator-reviewed stale Agent reconnect/retirement;
audit backlog/oldest-age metrics and aged SQL load test remain open.

The previous Minikube envplane profile and its data were deleted by explicit user
authorization. Kind and both bethunder profiles remain. envplane.local port 80
has an unresolved Docker listener conflict; frontend port-forward on 3000 works.
No Docker-wide restart is included in this code iteration.

Overall production-readiness decision remains NO-GO until these live gates close.
