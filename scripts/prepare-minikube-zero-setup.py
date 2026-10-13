#!/usr/bin/env python3
"""Verify a published zero-values candidate without creating a cluster or release."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone

SEMVER = r"[0-9]+\.[0-9]+\.[0-9]+"
DIGEST = r"sha256:[0-9a-f]{64}"
SHA = r"[0-9a-f]{40}"
IMAGES = {"control-plane": "api", "frontend": "frontend", "agent": "agent",
          "runner": "runner", "webhook": "webhook", "platform-reconciler": "platform-reconciler"}
CHARTS = {f"envplane-{name}" for name in
          ("control-plane", "frontend", "agent", "runner", "webhook", "e2e-workload")}
IDENTITY = ("https://github.com/" "Env" "Plane"
            "/deploy/.github/workflows/release-on-main.yaml@refs/heads/main")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(index, manifest):
    require(index.get("schemaVersion") == manifest.get("schemaVersion") == 1,
            "unsupported release schema")
    version, revision = index.get("version", ""), index.get("sourceRevision", "")
    require(re.fullmatch(SEMVER, version) and re.fullmatch(SHA, revision), "invalid release identity")
    require(index.get("channel") == "stable", "candidate is not stable")
    require(index.get("chart", {}).get("repository") == "oci://ghcr.io/envplane/envplane" and
            re.fullmatch(DIGEST, index["chart"].get("digest", "")), "invalid umbrella pin")
    require(manifest.get("umbrella") == {"name": "envplane", "version": version} and
            manifest.get("sourceRevision") == revision, "index/compatibility identity mismatch")
    images, charts = manifest.get("images", []), manifest.get("childCharts", [])
    require(len(images) == len(IMAGES) and {i.get("name") for i in images} == set(IMAGES),
            "missing, duplicate or unknown image")
    require(len(charts) == len(CHARTS) and {c.get("name") for c in charts} == CHARTS,
            "missing, duplicate or unknown child chart")
    for image in images:
        require(image.get("repository") == "ghcr.io/envplane/" + IMAGES[image["name"]] and
                re.fullmatch("sha-" + SHA, image.get("tag", "")) and
                re.fullmatch(DIGEST, image.get("digest", "")), "invalid image pin")
    for chart in charts:
        require(chart.get("repository") == "oci://ghcr.io/envplane/" + chart["name"] and
                re.fullmatch(SEMVER, chart.get("version", "")) and
                re.fullmatch(DIGEST, chart.get("digest", "")) and
                chart.get("sourceRevision") == revision, "invalid child chart pin")


def rendered_summary(rendered, manifest):
    # Inspect only workload metadata and image references. Never persist the
    # rendering: zero-values Helm rendering can generate random Secret data.
    images = sorted(set(re.findall(r'^\s+image:\s*["\']?([^\s"\']+)', rendered, re.M)))
    require(images and all(re.fullmatch(r"[^\s@]+@" + DIGEST, i) for i in images),
            "rendered workload contains an unpinned image")
    expected = {i["repository"] + "@" + i["digest"] for i in manifest["images"]}
    for image in images:
        if image.startswith("ghcr.io/envplane/"):
            require(image in expected, "rendered image differs from compatibility pin")
        else:
            require(image.split("@", 1)[0] in {"postgres", "redis", "postgres:16-alpine", "redis:7-alpine"},
                    "unexpected bundled data-service image")
    workloads = []
    for document in re.split(r"^---\s*$", rendered, flags=re.M):
        kind = re.search(r"^kind: (Deployment|StatefulSet)$", document, re.M)
        if kind:
            name = re.search(r"^metadata:\n\s+name:\s*[\"']?([^\s\"']+)", document, re.M)
            require(name is not None, "rendered workload has no name")
            workloads.append({"kind": kind[1], "name": name[1]})
    require({w["name"] for w in workloads} >= {
        "envplane-control-plane", "envplane-frontend", "envplane-control-plane-postgres",
        "envplane-control-plane-redis"}, "zero-values management workloads are incomplete")
    return {"images": images, "workloads": workloads}


def platforms(descriptor, expected_digest):
    require(descriptor.get("digest") == expected_digest, "registry image digest mismatch")
    found = {f"{m.get('platform', {}).get('os')}/{m.get('platform', {}).get('architecture')}"
             for m in descriptor.get("manifests", [])}
    require({"linux/arm64", "linux/amd64"} <= found, "image lacks required arm64/amd64 platforms")
    return ["linux/amd64", "linux/arm64"]


def run(command, stage, env=None):
    try:
        return subprocess.run(command, check=True, capture_output=True, text=True,
                              timeout=60, env=env).stdout
    except (OSError, subprocess.SubprocessError) as error:
        # Raw tool output can include rendered credentials. Only stage/error
        # class is safe to report; never print stdout/stderr on failure.
        raise ValueError(f"{stage} failed ({type(error).__name__})") from error


def pull(helm, repository, version, digest, directory, env):
    command = [helm, "pull", repository, "--version", version, "--destination", str(directory)]
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True,
                                timeout=60, env=env)
    except (OSError, subprocess.SubprocessError) as error:
        raise ValueError(f"anonymous chart pull failed ({type(error).__name__})") from error
    actual = re.findall(r"^Digest:\s*(sha256:[0-9a-f]{64})\s*$",
                        result.stdout + "\n" + result.stderr, re.M)
    require(actual == [digest], "published chart digest differs from frozen pin")
    return directory / f"{repository.rsplit('/', 1)[1]}-{version}.tgz"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-dir", type=Path, required=True,
                        help="downloaded versioned release index, bundle and release.json")
    parser.add_argument("--output-dir", type=Path, required=True, help="new directory for safe evidence")
    parser.add_argument("--profile", default="envplane")
    parser.add_argument("--kubernetes-version", default="1.35.9")
    parser.add_argument("--helm", default="helm")
    parser.add_argument("--buildx", type=Path,
                        default=Path.home() / ".docker/cli-plugins/docker-buildx")
    args = parser.parse_args()
    try:
        require(re.fullmatch(r"[a-z][a-z0-9-]{0,62}", args.profile), "invalid profile")
        require(re.fullmatch(SEMVER, args.kubernetes_version), "invalid Kubernetes pin")
        require(not args.output_dir.exists(), "output directory already exists; use a fresh evidence directory")
        indexes = list(args.release_dir.glob("envplane-*-release-index.json"))
        require(len(indexes) == 1, "exactly one versioned index is required")
        index_file = indexes[0]
        index = json.loads(index_file.read_text())
        manifest = json.loads((args.release_dir / "release.json").read_text())
        validate(index, manifest)
        bundle = index_file.with_name(index_file.name.replace(".json", ".sigstore.json"))
        run(["cosign", "verify-blob", "--bundle", str(bundle), "--certificate-identity", IDENTITY,
             "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com", str(index_file)],
            "release index signature")
        with tempfile.TemporaryDirectory(prefix="envplane-prepare-") as temporary:
            tmp = Path(temporary)
            registry = tmp / "registry.json"
            registry.write_text('{"auths":{}}\n')
            (tmp / "config.json").write_text('{"auths":{}}\n')
            env = dict(os.environ, DOCKER_CONFIG=str(tmp), HELM_REGISTRY_CONFIG=str(registry),
                       HELM_REPOSITORY_CONFIG=str(tmp / "repositories.yaml"))
            package = pull(args.helm, index["chart"]["repository"], index["version"],
                           index["chart"]["digest"], tmp, env)
            with tarfile.open(package) as archive:
                member = archive.extractfile("envplane/compatibility/release.json")
                require(member is not None and json.load(member) == manifest,
                        "downloaded compatibility differs from trusted chart content")
            metadata = run([args.helm, "show", "chart", str(package)], "chart metadata", env)
            require(re.search(r"^version: " + re.escape(index["version"]) + r"$", metadata, re.M),
                    "chart version differs from frozen pin")
            run([args.helm, "lint", str(package), "--strict"], "zero-values chart lint", env)
            rendering = run([args.helm, "template", "envplane", str(package), "--namespace", "envplane",
                             "--kube-version", args.kubernetes_version], "zero-values chart render", env)
            summary = rendered_summary(rendering, manifest)
            del rendering
            for chart in manifest["childCharts"]:
                pull(args.helm, chart["repository"], chart["version"], chart["digest"], tmp, env)
            references = sorted(set(summary["images"]) | {
                i["repository"] + "@" + i["digest"] for i in manifest["images"]})
            descriptors = []
            for reference in references:
                descriptor = json.loads(run([str(args.buildx), "imagetools", "inspect", "--format",
                                             "{{json .Manifest}}", reference], "anonymous image descriptor", env))
                descriptors.append({"reference": reference,
                                    "platforms": platforms(descriptor, reference.split("@", 1)[1])})
        candidates = {("deploy", manifest["sourceRevision"])}
        for image in manifest["images"]:
            repository = "deploy" if image["name"] == "platform-reconciler" else image["name"]
            candidates.add((repository, image["tag"][4:]))
        ci_command = [sys.executable, str(Path(__file__).with_name("validate-component-ci.py"))]
        for repository, revision in sorted(candidates):
            ci_command += ["--candidate", repository + "=" + revision]
        ci = json.loads(run(ci_command, "exact component CI"))
        report = {"schemaVersion": 1, "preparedAt": datetime.now(timezone.utc).isoformat(),
                  "decision": "PREPARED_NOT_DEPLOYED", "version": index["version"],
                  "chart": index["chart"], "sourceRevision": index["sourceRevision"],
                  "profile": args.profile, "kubernetesVersion": args.kubernetes_version,
                  "helmVersion": run([args.helm, "version", "--short"], "Helm version").strip(),
                  "verified": ["signed-index", "anonymous-umbrella-digest", "embedded-compatibility",
                               "zero-values-lint-render", "anonymous-child-chart-digests",
                               "anonymous-image-descriptors-both-architectures", "exact-component-ci"],
                  "rendered": summary, "imageDescriptors": descriptors, **ci,
                  "pending": ["cluster-capacity-and-storage", "cluster-rbac", "fresh-clean-install",
                              "first-run-owner-tenant", "authenticated-agent-runner", "fresh-cni-proof",
                              "lifecycle-and-scoped-copy", "nonempty-priced-finops", "management-dr",
                              "scm-and-provider-acceptance", "independent-sbom-provenance-verification"]}
        args.output_dir.mkdir(parents=True, mode=0o700)
        for source, name in [(index_file, "release-index.json"), (bundle, "release-index.sigstore.json"),
                             (args.release_dir / "release.json", "compatibility.json")]:
            shutil.copyfile(source, args.output_dir / name)
        (args.output_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Prepared {index['version']}: signed artifact and CI checks passed; nothing deployed.")
        print(f"Safe evidence: {args.output_dir.resolve()}")
        return 0
    except (ValueError, OSError, KeyError, TypeError, tarfile.TarError) as error:
        print(f"Preparation refused: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
