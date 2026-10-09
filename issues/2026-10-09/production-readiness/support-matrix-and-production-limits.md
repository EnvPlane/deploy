# Publish evidence-backed support matrix and production acceptance limits

Priority: P1 commercial-readiness gap. Status: OPEN.

The installation guide advertises Kubernetes 1.26+ and Helm 3.14+. The current clean-install pass exercises only Kubernetes v1.37.0 ARM64/containerd/kind local-path storage; it cannot establish compatibility for every advertised version, CNI, CSI, architecture or deployment mode. No consolidated approved production envelope was identified during this initial documentation inventory. This is a coverage/documentation gap, not proof that an untested version is broken.

Implementation prompt for Codex: inventory existing CI compatibility jobs and release evidence; publish a versioned support matrix with tested Kubernetes/Helm/CPU/CNI/CSI/Flux/DB/backend combinations and explicit experimental/excluded features. Define measurable capacity and SLO/RPO/RTO acceptance targets with product-owner approval. Add pinned representative CI jobs for the minimum and selected supported versions; reject unsupported configurations with actionable diagnostics where feasible. Update installation claims only from passing evidence, without treating a single developer cluster as production certification.

Acceptance: each supported combination links to repeatable test evidence for the release candidate; all missing coverage is visible; limits are approved, not invented; commercial claims align with the matrix.
