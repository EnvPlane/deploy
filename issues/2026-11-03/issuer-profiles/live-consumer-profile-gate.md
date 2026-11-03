# LIVE customer issuer profile remains gated

Status: deferred; sandbox configuration implemented, LIVE not authorized here.

Problem: the installation billing adapter currently hard-codes TEST scope. A
production selector without protocol support would misrepresent LIVE readiness.

Codex implementation prompt:

Inspect the current installation adapter and the separately owned issuer public
contract. After an accepted LIVE handoff, implement explicit LIVE scope validation
without reusing TEST sessions, merchants, enrollment bindings or trust implicitly.
Keep seller credentials out of customer clusters. Add mode/tenant/installation
isolation, replay, signed metadata and revocation tests; only then update the Helm
production-profile gate. Preserve backward-compatible sandbox behavior. Do not
deploy, charge, sign, issue/redeem licenses or change issuer resources without
separate authority. Provide exact consumer and issuer acceptance evidence.
