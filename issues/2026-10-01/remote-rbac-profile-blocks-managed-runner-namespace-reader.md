# Remote RBAC profile blocks managed Runner namespace reader

## Evidence

With EnvPlane `0.4.553`, remote reconciliation reaches the updated Runner
chart but Helm cannot patch the release-owned namespace reader for project
Runners. The remote installer identity is denied `patch` on the release-named
ClusterRole. Its ClusterRoleBinding is additionally rejected by the generated
ValidatingAdmissionPolicy because that policy permits only fixed read-only
capability roles and Agent capability bindings.

This prevents the reconciler from updating the exact `resourceNames` list used
by the Runner's ownership-checked cleanup. The retry remains safely blocked;
the target namespace is not deleted.

## Required implementation

1. Extend the rendered remote RBAC profile so the installer can create/update/
   delete only Helm-owned Runner namespace-reader ClusterRoles and bindings.
2. Restrict the admission rule to the canonical release-name pattern, Runner
   ServiceAccount in the configured runtime namespace, and the same Helm
   ownership labels and annotations as the managed release.
3. Validate that the ClusterRole contains only `namespaces`, concrete
   `resourceNames`, and `get`/`delete`; reject list, watch, wildcards and
   unrelated resources.
4. Preserve the existing prohibition on feature-writer parent bindings and
   unrelated ClusterRoleBindings.
5. Add renderer and negative-policy contract coverage, then verify a remote
   Runner chart upgrade can reconcile a new target namespace.

## Codex implementation prompt

Implement a narrow dynamic Runner namespace-reader allowance in
`scripts/render-remote-cluster-rbac-profile.sh`. Do not grant generic
ClusterRole create, patch, bind, escalate, or arbitrary ClusterRoleBinding
access. The generated ValidatingAdmissionPolicy must enforce the exact Helm
release ownership and ClusterRole rule shape. Run the remote profile contract
tests and a rendered managed-remote Runner chart test.
