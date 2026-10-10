#!/usr/bin/env python3
"""Build host driver + matching Linux Runner OCI helper locally; never load/push.

The helper uses the upstream Runner main and current sibling contracts. Builds
are local-integration evidence, not published-module compatibility evidence.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tarfile
import io

BASE = "alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6"


def execute(args, cwd, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True, timeout=300)


def finalize(output, run_id, architecture):
    build = json.loads((output / "build.json").read_text())
    if build["runID"] != run_id or build["architecture"] != architecture:
        raise ValueError("existing build identity mismatch")
    metadata = json.loads((output / "image-metadata.json").read_text())
    digest = metadata["containerimage.digest"]
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
        raise ValueError("invalid existing helper digest")
    with tarfile.open(output / "helper.oci.tar") as archive:
        manifest_bytes = archive.extractfile("blobs/sha256/" + digest.split(":")[1]).read()
        if hashlib.sha256(manifest_bytes).hexdigest() != digest.split(":")[1]:
            raise ValueError("helper manifest integrity mismatch")
        manifest = json.loads(manifest_bytes)
        found = []
        for layer in manifest["layers"]:
            raw = archive.extractfile("blobs/sha256/" + layer["digest"].split(":")[1]).read()
            if hashlib.sha256(raw).hexdigest() != layer["digest"].split(":")[1]:
                raise ValueError("helper layer integrity mismatch")
            with tarfile.open(fileobj=io.BytesIO(raw), mode="r:*") as files:
                for item in files:
                    if item.name.lstrip("./") == "usr/local/bin/envplane-runner":
                        found.append(hashlib.sha256(files.extractfile(item).read()).hexdigest())
    binary_sha = hashlib.sha256((output / "envplane-runner").read_bytes()).hexdigest()
    if found != [binary_sha] or binary_sha != build["helperBinarySHA256"]:
        raise ValueError("archive helper binary does not match host build")
    build.update({"image": "ghcr.io/envplane/runner@" + digest,
                  "archiveBinaryVerified": True,
                  "hostDriverSHA256": hashlib.sha256((output / "pvc-copy-live-driver").read_bytes()).hexdigest(),
                  "archiveSHA256": hashlib.sha256((output / "helper.oci.tar").read_bytes()).hexdigest()})
    (output / "build.json").write_text(json.dumps(build, indent=2) + "\n")
    print(json.dumps(build, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--architecture", choices=("arm64", "amd64"), default="arm64")
    parser.add_argument("--skip-image", action="store_true", help="build binaries only; helper digest remains unavailable")
    parser.add_argument("--finalize-existing-image", action="store_true", help="verify an existing local OCI archive against its host binary")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{16}", args.run_id):
        parser.error("run ID must be 16 lowercase hexadecimal characters")
    output = Path(args.output_dir).resolve()
    if args.finalize_existing_image:
        finalize(output, args.run_id, args.architecture)
        return
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    workspace = Path(__file__).resolve().parents[2]
    source = Path(__file__).resolve().parent / "pvc-copy-live-driver"
    with tempfile.TemporaryDirectory(prefix="envplane-pvc-copy-build-") as directory:
        temporary = Path(directory)
        module = temporary / "module";module.mkdir()
        shutil.copyfile(source / "main.go", module / "main.go")
        # Ephemeral module, no edits to Runner/contracts/gitops or parent go.work.
        (module / "go.mod").write_text("module github.com/envplane/runner/pvc-copy-live-driver\n\ngo 1.26.9\n\n"
            "require (\n github.com/envplane/runner v0.0.0\n github.com/envplane/contracts v0.1.109\n)\n\n" +
            "\n".join(f"replace github.com/envplane/{name} => {workspace / name}" for name in ("runner", "contracts", "gitops")) + "\n")
        env = {**os.environ, "GOWORK": "off", "GOPROXY": "off", "GOSUMDB": "off", "GOTOOLCHAIN": "local",
               "GOCACHE": str(temporary / "go-cache")}
        execute(["go", "build", "-mod=mod", "-trimpath", "-o", str(output / "pvc-copy-live-driver"), "."], module, env)
        execute(["go", "build", "-mod=mod", "-trimpath", "-o", str(output / "envplane-runner"),
                 "github.com/envplane/runner/cmd/envplane-runner"], module,
                {**env, "CGO_ENABLED": "0", "GOOS": "linux", "GOARCH": args.architecture})
    binary_sha = hashlib.sha256((output / "envplane-runner").read_bytes()).hexdigest()
    build = {"runID": args.run_id, "architecture": args.architecture, "helperBinarySHA256": binary_sha,
             "hostDriverSHA256": hashlib.sha256((output / "pvc-copy-live-driver").read_bytes()).hexdigest(),
             "helperBase": BASE, "liveClusterWrites": 0, "pushed": False}
    for name in ("runner", "contracts", "gitops"):
        build[name + "Commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=workspace / name, text=True).strip()
        build[name + "WorktreeDirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=workspace / name, text=True).strip())
    if not args.skip_image:
        # No package installation, remote push, credentials or kind load. The
        # imported OCI manifest must be verified by the owner before execution.
        (output / "Dockerfile").write_text(f"FROM {BASE}\nCOPY envplane-runner /usr/local/bin/envplane-runner\nUSER 10001:10001\nENTRYPOINT [\"/usr/local/bin/envplane-runner\"]\n")
        tag = f"ghcr.io/envplane/runner:pvccopy-live-{args.run_id}"
        execute(["docker", "buildx", "build", "--network=none", "--pull=false", "--platform", f"linux/{args.architecture}",
                 "--provenance=false", "--sbom=false", "--tag", tag,
                 "--metadata-file", str(output / "image-metadata.json"),
                 "--output", f"type=oci,dest={output / 'helper.oci.tar'}", str(output)], output)
        metadata = json.loads((output / "image-metadata.json").read_text())
        digest = metadata["containerimage.digest"]
        if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
            raise ValueError("unexpected helper manifest digest")
        build["image"] = "ghcr.io/envplane/runner@" + digest
        build["archiveSHA256"] = hashlib.sha256((output / "helper.oci.tar").read_bytes()).hexdigest()
        build["localTag"] = tag
    (output / "build.json").write_text(json.dumps(build, indent=2) + "\n")
    if args.skip_image:
        print(json.dumps(build, indent=2))
    else:
        finalize(output, args.run_id, args.architecture)


if __name__ == "__main__":
    main()
