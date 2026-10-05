# Supplemental remote project binding access

Status: implemented; operator review and live application pending.

Existing exact-name installer profiles covered cluster-runtime Agent bindings
but not new project releases. The project app failed on get of its capability
binding while the cluster runtime remained healthy (umbrella 0.4.605).

Run bash scripts/render-remote-project-binding-access.sh --cluster-id TARGET
--project-id PROJECT [--runtime-namespace NAME] for a credential-free supplemental
profile. IDs must be DNS labels. It derives all three binding identities from
the project Agent release and grants only get/update/patch/delete of those names
to the existing remote installer. It does not create a token or grant bind,
escalate, create, wildcard access, or baseline workload access. Review before apply.
The renderer does not replace the complete remote installer admission profile.

Codex prompt: keep renderer identities in parity with the Agent chart and backend
remoteAgentCapabilityBindingNames; test arbitrary IDs, custom runtime namespace,
malformed inputs, exact names, and absence of broader RBAC. Do not automatically
apply the profile as part of an unrelated UI test.
