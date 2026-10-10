#!/usr/bin/env python3
"""Load a verified local helper into the exact isolated kind node, never push."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def command(args):
    return subprocess.check_output(args, text=True, timeout=90).strip()


def parse_images(output):
    return {fields[0]: fields[2] for line in output.splitlines()[1:] if len(fields := line.split()) >= 3}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-record", required=True)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--cluster-uid", required=True)
    parser.add_argument("--authorize-fixture", required=True)
    args = parser.parse_args()
    build_path = Path(args.build_record).resolve()
    build = json.loads(build_path.read_text())
    run_id = build["runID"]
    if not re.fullmatch(r"[a-f0-9]{16}", run_id) or args.authorize_fixture != run_id or not build.get("archiveBinaryVerified"):
        raise ValueError("explicit verified fixture build authorization required")
    archive = build_path.parent / "helper.oci.tar"
    if hashlib.sha256(archive.read_bytes()).hexdigest() != build["archiveSHA256"]:
        raise ValueError("helper archive changed")
    image = build["image"]
    if not re.fullmatch(r"ghcr.io/envplane/runner@sha256:[a-f0-9]{64}", image):
        raise ValueError("unexpected helper image")
    context = "kind-envplane-readiness-682"
    uid = command(["kubectl", "--kubeconfig", args.kubeconfig, "--context", context, "get", "namespace", "kube-system", "-o", "jsonpath={.metadata.uid}"])
    if uid != args.cluster_uid:
        raise ValueError("isolated cluster UID changed")
    node = "envplane-readiness-682-control-plane"
    if command(["kind", "get", "nodes", "--name", "envplane-readiness-682"]) != node:
        raise ValueError("unexpected kind node topology")
    tag = "ghcr.io/envplane/runner:pvccopy-live-" + run_id
    native = ["docker", "exec", node, "ctr", "--namespace", "k8s.io", "images"]
    before = parse_images(command([*native, "ls"]))
    digest = image.split("@", 1)[1]
    for ref in (image, tag):
        if ref in before and before[ref] != digest:
            raise ValueError("fixture image name already has foreign digest; never overwrite")
    command(["kind", "load", "image-archive", str(archive), "--name", "envplane-readiness-682"])
    loaded = parse_images(command([*native, "ls"]))
    if loaded.get(tag) != digest:
        raise ValueError("imported tag digest mismatch")
    # kind import registers a tag, not necessarily the repository@digest CRI key.
    if image not in loaded:
        command([*native, "tag", tag, image])
    after = parse_images(command([*native, "ls"]))
    if after.get(image) != digest:
        raise ValueError("immutable helper alias missing")
    print(json.dumps({"loadedFixtureImage": image, "clusterUID": uid, "node": node, "pushed": False}, indent=2))


if __name__ == "__main__":
    main()
