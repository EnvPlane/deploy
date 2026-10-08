# Authorized Calico candidate creation and real NetworkPolicy probe

Status: candidate created and bounded traffic probe passed. **Not a workload/data
cutover; not a production migration acceptance or API readiness update.**
Executed 2026-10-08, after direct authorization for this distinct candidate.

## Reviewed gate and preserved boundaries

Source context: bethunder-local. Target: bethunder-policy-candidate.
Minikube binary: v1.39.0, commit 7a9f6a841470a207de8cf4bafcccee0969d8ba10.
Kubernetes: v1.35.1; Docker driver; candidate runtime containerd://2.3.4.
Candidate limit: 4 CPUs / 6 GiB; source 6 GiB and management 4 GiB unchanged.
Docker total memory: 12528103424 bytes (11.67 GiB); no limit changes.

Creation used the reviewed planner inventory/digest gate and exact target approval.
Canonical plan SHA256:
`180aad11be80be20c261bdd7f5c29dc370eadc4e17abd0a4de490383dc188d50`.
Inventory SHA256:
`232957b40e7149b7f5412ed28910634f656d090bb65f32617bb1b948ad449b58`.
Read-only, mode-0600 inventory/plan files are in /private/tmp; they contain no
Secrets, raw kubeconfig, environment values or source workload data.

Planner adds `--keep-context --interactive=false`. Before and after: current
kubectl context `envplane`; default Minikube profile `minikube`. No contexts/routes
switched, no profiles/PVs deleted, no source CNI modified and no source Secrets,
data or workloads copied. Source and management nodes remained Ready.
Before/after comparison: source cluster UID and complete projected namespaces,
PVC and PV metadata inventories unchanged (14 namespaces, 11 PVCs, 324 PVs).

## Versioned upstream review and observed artifact identity

Minikube v1.39.0 embeds Calico configuration and fixes Calico version to v3.32.2;
no generic latest engine installation was used. Existing bridge networking was
not replaced or layered. The separate candidate's actual Calico pods were Ready:

| Image | Observed image digest |
| --- | --- |
| quay.io/calico/node:v3.32.2 | sha256:99b03fe91e8bfbcb153ae65ef4b701b24ce541ffdd74ff314eb041096008f7fd |
| quay.io/calico/cni:v3.32.2 | sha256:0ef740bc587f25565905adf1d1f61a7faff0d571c449c6bdd789feed743d3ef7 |
| quay.io/calico/kube-controllers:v3.32.2 | sha256:7870b67ebb13fabc3005252b44fe6e78b21635649bd3072b80afa1684b6565d0 |

Primary references:
- https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/minikube/cni/calico.go
- https://github.com/kubernetes/minikube/blob/v1.39.0/pkg/minikube/bootstrapper/images/images.go
- https://minikube.sigs.k8s.io/docs/commands/start/ (--keep-context)

The archived Calico 3.32 requirements URL could not be fetched during review;
current latest docs describe 3.33 and were not treated as a 3.32 certification.
Observed v1.35.1 bootstrap, Calico readiness and real traffic probe establish
bounded candidate interoperability, not all topologies or a vendor support SLA.

## Actual Agent probe

Built the existing Agent CLI locally; no Agent source changes. Invocation:

```sh
/private/tmp/envplane-networkpolicy-probe-candidate \
  --context bethunder-policy-candidate --generation 1 --authorize-test-resources
```

Probe owned only `envplane-netpol-probe-5301550a097a0edd325d776f`, three temporary
Pods and its NetworkPolicy. It checks positive baseline, repeated fresh TCP HTTP
ingress-deny connections, selected-label allow with denied-peer control,
egress-deny with allowed-peer control and policy-removal recovery.

Actual emitted safe report (CLI exit 0):

```json
{"schemaVersion":1,"clusterUID":"bbf1a88a-dbf0-4a28-a730-521193d56275","generation":1,"checkedAt":"2026-10-08T12:54:25.061526Z","scope":"single-node-pod-ipv4-tcp","ingress":"passed","egress":"passed","state":"passed","reason":"measured","cleanupComplete":true}
```

Independent post-check found the exact owned namespace absent and no candidate
NetworkPolicies/probe Pods remaining. No unrelated resources were deleted.
After stabilization measured Docker usage: candidate 963.1 MiB / 6 GiB,
source 2.945 GiB / 6 GiB, management 1.618 GiB / 4 GiB,
private gateway 120.1 MiB. Resource limits were not expanded.

## Remaining acceptance / Codex implementation prompt

Parent owns HTTPS identity-bound report upload/readiness, telemetry and payments.
This was offline generation=1 evidence, not a server-issued lease or registered
runtime Agent, and must **not** be imported as trusted API readiness evidence.
Obtain a fresh authenticated lease and repeat the probe through verified HTTPS.

For further migration, first get explicit workload/data/cutover authorization,
encrypted restore-tested backups and a reconciliation/ownership plan. Test
cross-namespace, Service-IP, DNS/API/SCM/management/Hybrid paths, multi-node if
needed, and restart persistence; preserve original applications/data until all
checks pass. No restart/cutover/import/retirement was executed in this iteration.
The original bethunder-local is still the previously non-enforcing source, not
silently fixed by creating this candidate.
