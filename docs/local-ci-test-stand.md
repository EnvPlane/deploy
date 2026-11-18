# Local continuously updated TEST stand

Use a dedicated Kind cluster named `envplane-ci-test`, with kubeconfig at
`~/.local/state/envplane-ci-test/kubeconfig`. Do not merge this kubeconfig into
your primary one. The cluster and its volumes persist between runs. The
local fixture allows anonymous API access: forward only to `127.0.0.1`, never
add a public listener or use real data or credentials.

Run `bash scripts/reconcile-local-ci-test.sh` via a local scheduler as the
cluster operator. Dependencies: Helm 4, kubectl, cosign, gh (authenticated to
read release assets), and jq. Use `kubectl --kubeconfig <path> --context
kind-envplane-ci-test -n envplane port-forward --address=127.0.0.1
svc/envplane-frontend 13000:3000` for UI access. The scheduler and UI forwarding
require the local host and Docker to be running.

CI publishes the umbrella; the stand pulls only the latest stable index
signed by deploy's release-on-main workflow and matches the fetched OCI
digest before install. It refuses downgrades and uses Helm rollback on
failure. An unhealthy release or stale lock requires operator inspection;
do not clear a lock while a run is active. No hosted runner has cluster
credentials.

External billing and activation stay disabled here until a separately
accepted TEST issuer and isolated test identity are configured. Do not
reuse the GEN20 installation identity, credentials, or purchase on this
stand. This stand is not evidence of live payment or license issuance.
