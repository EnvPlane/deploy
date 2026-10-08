#!/usr/bin/env python3
"""Explicit, fail-closed bridge for a reviewed existing restricted feature."""
import argparse
import json
import subprocess
import sys


def call(context, args, data=None):
    result = subprocess.run(["kubectl", "--context", context] + args, input=data, capture_output=True)
    if result.returncode:
        raise ValueError("Reviewed Flux policy bridge operation failed")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True)
    parser.add_argument("--approve-target", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--feature", required=True)
    parser.add_argument("--base-namespace", action="append", required=True)
    args = parser.parse_args()
    if args.context != args.approve_target or not args.namespace.startswith("envplane-pr-"):
        raise ValueError("Exact candidate and owned feature namespace required")
    if args.root == args.feature or len(args.base_namespace) != len(set(args.base_namespace)):
        raise ValueError("Distinct Flux objects and unique base namespace allowlist required")
    policy = json.loads(call(args.context, ["-n", args.namespace, "get", "networkpolicy", "envplane-feature-egress", "-o", "json"]))
    peers = [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": name}}} for name in args.base_namespace]
    if policy["spec"]["egress"][0]["to"] != peers or policy["spec"]["policyTypes"] != ["Egress"]:
        raise ValueError("Existing policy is not the reviewed restricted mode")
    selector = {"matchExpressions": [{"key": "envplane.io/pvc-exporter", "operator": "DoesNotExist"}]}
    if policy["spec"].get("podSelector") not in ({}, selector):
        raise ValueError("Custom policy selector requires separate review")
    patch = [{"op": "test", "path": "/spec/egress/0/to", "value": peers}, {"op": "add", "path": "/spec/podSelector", "value": {"matchExpressions": [{"key": "envplane.io/pvc-exporter", "operator": "DoesNotExist"}]}}, {"op": "add", "path": "/spec/egress/-", "value": {"to": [{"podSelector": {}}]}}]
    feature_patches = [{"target": {"group": "networking.k8s.io", "version": "v1", "kind": "NetworkPolicy", "name": "envplane-feature-egress", "namespace": args.namespace}, "patch": json.dumps(patch)}]
    for name, kind, component, path in (("backend-data", "PersistentVolumeClaim", "backend", "/metadata/labels/app.kubernetes.io~1component"), ("mysql-data", "PersistentVolumeClaim", "mysql", "/metadata/labels/app.kubernetes.io~1component"), ("backend", "Deployment", "backend", "/spec/template/metadata/labels/app.kubernetes.io~1component"), ("frontend", "Deployment", "frontend", "/spec/template/metadata/labels/app.kubernetes.io~1component"), ("mysql", "StatefulSet", "mysql", "/spec/template/metadata/labels/app.kubernetes.io~1component")):
        feature_patches.append({"target": {"kind": kind, "name": name, "namespace": args.namespace}, "patch": json.dumps([{"op": "add", "path": path, "value": component}])})
    root_patches = [{"target": {"group": "kustomize.toolkit.fluxcd.io", "version": "v1", "kind": "Kustomization", "name": args.feature, "namespace": "flux-system"}, "patch": json.dumps([{"op": "add", "path": "/spec/patches", "value": feature_patches}])}]
    # Accept only the exact earlier bridge produced by this tool, not arbitrary
    # operator patches. The replacement narrows selectors for exporter isolation.
    old_feature = json.loads(json.dumps(feature_patches))
    old_feature[0]["patch"] = json.dumps([patch[0], patch[-1]])
    old_root = [{"target": root_patches[0]["target"], "patch": json.dumps([{"op": "add", "path": "/spec/patches", "value": old_feature}])}]
    legacy_root = json.loads(json.dumps(root_patches))
    legacy_root[0]["target"].pop("namespace")
    legacy_old_root = json.loads(json.dumps(old_root))
    legacy_old_root[0]["target"].pop("namespace")
    captured = {}
    for name, patches in ((args.root, root_patches), (args.feature, feature_patches)):
        current = json.loads(call(args.context, ["-n", "flux-system", "get", "kustomization", name, "-o", "json"]))
        previous = old_root if name == args.root else old_feature
        accepted = (None, [], patches, previous, legacy_root, legacy_old_root) if name == args.root else (None, [], patches, previous)
        if current["spec"].get("patches") not in accepted:
            raise ValueError("Existing operator patches require separate review")
        if not current["spec"].get("suspend", False):
            raise ValueError("Require paused target Flux before configuring bridge")
        captured[name] = current
    runtime_patch = list(patch)
    if policy["spec"]["egress"].count(patch[-1]["value"]) > 1:
        raise ValueError("Duplicate existing same-namespace rules need review")
    if patch[-1]["value"] in policy["spec"]["egress"]:
        runtime_patch.pop()
    runtime_patch = [{"op": "test", "path": "/metadata/uid", "value": policy["metadata"]["uid"]},
                     {"op": "test", "path": "/metadata/resourceVersion", "value": policy["metadata"]["resourceVersion"]}] + runtime_patch
    for name, patches in ((args.root, root_patches), (args.feature, feature_patches)):
        identity = captured[name]["metadata"]
        update = [{"op": "test", "path": "/metadata/uid", "value": identity["uid"]},
                  {"op": "test", "path": "/metadata/resourceVersion", "value": identity["resourceVersion"]},
                  {"op": "test", "path": "/spec/suspend", "value": True},
                  {"op": "add", "path": "/spec/patches", "value": patches}]
        call(args.context, ["-n", "flux-system", "patch", "kustomization", name, "--type=json", "--patch-file=/dev/stdin"], json.dumps(update).encode())
    call(args.context, ["-n", args.namespace, "patch", "networkpolicy", "envplane-feature-egress", "--type=json", "--patch-file=/dev/stdin"], json.dumps(runtime_patch).encode())
    print(json.dumps({"target": args.context, "feature": args.feature, "reviewedRestrictedPolicyBridge": True, "denyAllUnchanged": True}))


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, OSError):
        print("Scoped policy bridge rejected; no broad allow or source change", file=sys.stderr)
        sys.exit(1)
