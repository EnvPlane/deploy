#!/usr/bin/env python3
"""Redacted inventory and administrator-gated *new cluster* alternative.

Never modifies the source cluster, node CNI files, policies, workloads or data.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode:
        # Tool stderr can include credential/plugin output; never persist or echo it.
        raise ValueError(f"Command failed ({args[0]}), exit {result.returncode}")
    return result.stdout


def get(context, resource, namespace=None):
    args = ["kubectl", "--context", context, "--request-timeout=30s", "get", resource]
    args += ["-n", namespace] if namespace else ["-A"]
    return json.loads(command(args + ["-o", "json"]))


def reference(item):
    meta = item["metadata"]
    return {key: meta[key] for key in ("name", "namespace", "uid") if key in meta}


def inventory(context):
    identity = reference(get(context, "namespace/kube-system"))
    nodes = get(context, "nodes")["items"]
    summary = {"context": context, "clusterIdentity": identity,
               "collectedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "nodes": [], "resources": {}, "hostNetworkFacts": "requires administrator review"}
    for node in nodes:
        spec, status = node.get("spec", {}), node.get("status", {})
        info = status.get("nodeInfo", {})
        summary["nodes"].append({**reference(node), "podCIDRs": spec.get("podCIDRs", []),
                                 "ready": any(c.get("type") == "Ready" and c.get("status") == "True"
                                              for c in status.get("conditions", [])),
                                 "runtime": info.get("containerRuntimeVersion"),
                                 "kernel": info.get("kernelVersion"),
                                 "kubernetes": info.get("kubeletVersion")})
    # No Secrets, ConfigMaps, raw manifests, environment, annotations or kubeconfigs.
    for resource in ("namespaces", "pods", "services", "endpointslices", "ingresses",
                     "persistentvolumeclaims", "persistentvolumes", "storageclasses", "networkpolicies"):
        rows = []
        for item in get(context, resource)["items"]:
            row = reference(item)
            spec = item.get("spec", {})
            if resource == "pods":
                row.update(node=spec.get("nodeName"), phase=item.get("status", {}).get("phase"),
                           images=[c.get("image") for c in spec.get("containers", [])])
            elif resource == "services":
                row.update(type=spec.get("type"), clusterIP=spec.get("clusterIP"))
            elif resource == "persistentvolumeclaims":
                row.update(volumeName=spec.get("volumeName"), storageClassName=spec.get("storageClassName"))
            elif resource == "persistentvolumes":
                row.update(reclaimPolicy=spec.get("persistentVolumeReclaimPolicy"),
                           claimRef={k: spec.get("claimRef", {}).get(k) for k in ("namespace", "name", "uid")})
            rows.append(row)
        summary["resources"][resource] = sorted(rows, key=lambda r: (r.get("namespace", ""), r["name"]))
    return summary


def write_private(path, value):
    # Exclusive create prevents overwrite and symlink following.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        json.dump(value, handle, indent=2)
        handle.write("\n")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def profiles():
    data = json.loads(command(["minikube", "profile", "list", "-o", "json"]))
    # Both stopped/invalid profiles are collisions; failures are never treated as absence.
    if not isinstance(data, dict) or not any(key in data for key in ("valid", "invalid")):
        raise ValueError("Unrecognized profile inventory")
    for group in ("valid", "invalid"):
        if not isinstance(data.get(group, []), list):
            raise ValueError("Unrecognized profile inventory")
    return {p["Name"] for group in ("valid", "invalid") for p in data.get(group, [])}


def make_plan(source, target, version, snapshot):
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,49}", target) or target == source:
        raise ValueError("Target must be a distinct explicit profile name")
    if not re.fullmatch(r"v1\.\d+\.\d+", version):
        raise ValueError("Pin an exact Kubernetes patch version")
    return {"schemaVersion": 1, "strategy": "new-cluster-calico", "sourceContext": source,
            "sourceClusterUID": snapshot["clusterIdentity"]["uid"], "targetProfile": target,
            "inventorySHA256": digest(snapshot), "kubernetesVersion": version,
            "command": ["minikube", "start", "-p", target, "--driver=docker", "--cni=calico",
                        "--kubernetes-version=" + version, "--cpus=4", "--memory=6g",
                        "--keep-context", "--interactive=false"],
            "preserveSource": True, "acceptance": "UNVERIFIED: traffic probe and restore required",
            "rollback": "Keep source unchanged; do not cut over before acceptance. No automatic deletion."}


def execute_plan(plan, snapshot, expected_hash, approve):
    if digest(plan) != expected_hash or approve != plan["targetProfile"]:
        raise ValueError("Require reviewed plan SHA256 and exact target approval")
    rebuilt = make_plan(plan["sourceContext"], plan["targetProfile"], plan["kubernetesVersion"], snapshot)
    if plan != rebuilt:
        raise ValueError("Plan is altered or does not match inventory")
    if plan["targetProfile"] in profiles():
        raise ValueError("Target profile already exists; refusing CNI changes/recreation")
    fresh = inventory(plan["sourceContext"])
    original = dict(snapshot)
    fresh.pop("collectedAt", None)
    original.pop("collectedAt", None)
    if fresh != original:
        raise ValueError("Source inventory changed; recollect and review")
    # Existing kube contexts may point to a non-minikube cluster with this name.
    contexts = command(["kubectl", "config", "get-contexts", "-o", "name"]).splitlines()
    if plan["targetProfile"] in contexts:
        raise ValueError("Target kube context already exists; refusing overwrite")
    command(plan["command"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    collect = sub.add_parser("inventory")
    collect.add_argument("--context", required=True)
    collect.add_argument("--out", required=True)
    plan = sub.add_parser("plan")
    plan.add_argument("--inventory", required=True)
    plan.add_argument("--target", required=True)
    plan.add_argument("--kubernetes-version", required=True)
    plan.add_argument("--out", required=True)
    apply = sub.add_parser("apply-new-cluster")
    apply.add_argument("--plan", required=True)
    apply.add_argument("--inventory", required=True)
    apply.add_argument("--reviewed-sha256", required=True)
    apply.add_argument("--approve-target", required=True)
    args = parser.parse_args()
    try:
        if args.mode == "inventory":
            write_private(args.out, inventory(args.context))
        elif args.mode == "plan":
            snapshot = json.loads(Path(args.inventory).read_text())
            value = make_plan(snapshot["context"], args.target, args.kubernetes_version, snapshot)
            write_private(args.out, value)
            print("Review plan; canonical SHA256:", digest(value))
        else:
            execute_plan(json.loads(Path(args.plan).read_text()), json.loads(Path(args.inventory).read_text()),
                         args.reviewed_sha256, args.approve_target)
            print("New cluster created; isolation NOT verified, no source cutover performed")
    except (ValueError, KeyError, OSError) as exc:
        print("Migration refused:", type(exc).__name__, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
