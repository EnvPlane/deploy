#!/usr/bin/env python3
"""Encrypted exact-namespace migration configuration; workloads stay stopped.

No plaintext config/Secret bundle is persisted, no source writes, no source
Helm history, auto-generated service-account tokens or Kubernetes system objects
are imported. Target restore requires the encrypted bundle checksum and distinct
source/target cluster identities. Normal runtime reconciliation resumes later.
"""
import argparse
import copy
import hashlib
import json
import os
import subprocess
import sys


def command(args, data=None):
    result = subprocess.run(args, input=data, capture_output=True)
    if result.returncode:
        raise ValueError("Scoped configuration command failed")
    return result.stdout


def get(context, kind, namespace=None):
    args = ["kubectl", "--context", context, "get", kind]
    if namespace:
        args += ["-n", namespace]
    return json.loads(command(args + ["-o", "json"]))


def clean(obj):
    obj = copy.deepcopy(obj)
    obj.pop("status", None)
    meta = obj["metadata"]
    for key in ("uid", "resourceVersion", "generation", "creationTimestamp", "managedFields", "ownerReferences", "deletionTimestamp", "deletionGracePeriodSeconds", "finalizers"):
        meta.pop(key, None)
    annotations = meta.get("annotations", {})
    annotations.pop("kubectl.kubernetes.io/last-applied-configuration", None)
    if obj["kind"] == "Namespace":
        obj.pop("spec", None)
    if obj["kind"] == "ServiceAccount":
        obj.pop("secrets", None)
    if obj["kind"] == "Service":
        spec = obj["spec"]
        for key in ("clusterIPs", "ipFamilies", "ipFamilyPolicy", "healthCheckNodePort"):
            spec.pop(key, None)
        if spec.get("clusterIP") != "None":
            spec.pop("clusterIP", None)
        for port in spec.get("ports", []):
            port.pop("nodePort", None)
    if obj["kind"] == "PersistentVolumeClaim":
        obj["spec"].pop("volumeName", None)
        for key in list(annotations):
            if key.startswith("pv.kubernetes.io/") or key.startswith("volume.kubernetes.io/"):
                del annotations[key]
    if obj["kind"] in ("Deployment", "StatefulSet"):
        obj["spec"]["replicas"] = 0
    if obj["kind"] in ("Kustomization", "GitRepository"):
        obj["spec"]["suspend"] = True
    return obj


def sha(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1048576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def snapshot(source, target, namespaces, recipient, archive):
    if source == target or not namespaces or len(set(namespaces)) != len(namespaces) or not recipient.startswith("age1"):
        raise ValueError("Explicit distinct contexts, scopes and encryption required")
    source_uid = get(source, "namespace/kube-system")["metadata"]["uid"]
    target_uid = get(target, "namespace/kube-system")["metadata"]["uid"]
    if source_uid == target_uid:
        raise ValueError("Source and target alias forbidden")
    objects, cluster_roles = [], set()
    for namespace in namespaces:
        objects.append(clean(get(source, "namespace/" + namespace)))
        kinds = ["serviceaccounts", "configmaps", "secrets", "roles", "rolebindings"]
        if namespace != "flux-system":
            kinds += ["persistentvolumeclaims", "services", "deployments", "statefulsets", "ingresses", "networkpolicies"]
        for kind in kinds:
            items = get(source, kind, namespace)["items"]
            if kind == "secrets":
                latest = {}
                filtered = []
                for item in items:
                    if item.get("type") == "kubernetes.io/service-account-token":
                        continue
                    if item.get("type") == "helm.sh/release.v1":
                        labels = item["metadata"].get("labels", {})
                        name = labels.get("name", "")
                        if namespace == "flux-system" or not name or labels.get("status") != "deployed":
                            continue
                        version = int(labels.get("version", "0"))
                        if name not in latest or int(latest[name]["metadata"]["labels"]["version"]) < version:
                            latest[name] = item
                    else:
                        filtered.append(item)
                items = filtered + list(latest.values())
            for item in items:
                if kind == "configmaps" and item["metadata"]["name"] == "kube-root-ca.crt":
                    continue
                if kind == "rolebindings" and item["roleRef"]["kind"] == "ClusterRole":
                    cluster_roles.add(item["roleRef"]["name"])
                objects.append(clean(item))
    bindings = get(source, "clusterrolebindings")["items"]
    for binding in bindings:
        if any(s.get("namespace") == "envplane-system" for s in binding.get("subjects", [])):
            objects.append(clean(binding))
            cluster_roles.add(binding["roleRef"]["name"])
    for name in sorted(cluster_roles):
        if name in ("admin", "edit", "view", "cluster-admin") or name.startswith("system:"):
            continue
        objects.append(clean(get(source, "clusterrole/" + name)))
    for kind in ("gitrepositories.source.toolkit.fluxcd.io", "kustomizations.kustomize.toolkit.fluxcd.io"):
        for obj in get(source, kind, "flux-system")["items"]:
            objects.append(clean(obj))
    bundle = {"schemaVersion": 1, "source": source, "target": target, "sourceUID": source_uid, "targetUID": target_uid, "namespaces": namespaces, "objects": objects}
    with os.fdopen(os.open(archive, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), "wb") as out:
        result = subprocess.run(["age", "-r", recipient], input=json.dumps(bundle).encode(), stdout=out, stderr=subprocess.DEVNULL)
        if result.returncode:
            raise ValueError("Encrypted configuration export failed")
    print(json.dumps({"encrypted": True, "objectCount": len(objects), "archiveSHA256": sha(archive), "sourceUntouched": True}))


def restore(archive, expected, identity, target, approved):
    if target != approved or sha(archive) != expected or os.stat(identity).st_mode & 0o077 or os.path.islink(identity):
        raise ValueError("Reviewed encrypted checksum, private identity and exact target approval required")
    bundle = json.loads(command(["age", "-d", "-i", identity, archive]))
    if bundle["target"] != target or bundle["source"] == target or bundle["sourceUID"] == bundle["targetUID"]:
        raise ValueError("Wrong target")
    if get(target, "namespace/kube-system")["metadata"]["uid"] != bundle["targetUID"] or get(bundle["source"], "namespace/kube-system")["metadata"]["uid"] != bundle["sourceUID"]:
        raise ValueError("Cluster identity drift")
    ranks = {"Namespace": 0, "ClusterRole": 1, "ServiceAccount": 2, "Secret": 3, "ConfigMap": 4, "Role": 5, "ClusterRoleBinding": 6, "RoleBinding": 6, "PersistentVolumeClaim": 7, "Service": 8, "Deployment": 9, "StatefulSet": 9, "Ingress": 10, "NetworkPolicy": 10, "GitRepository": 11, "Kustomization": 12}
    for item in sorted(bundle["objects"], key=lambda item: ranks[item["kind"]]):
        namespace = item["metadata"].get("namespace")
        # The candidate has its own pinned Flux installation. Do not adopt or
        # override its controller identities using the source Helm release.
        if namespace == "flux-system" and item["kind"] == "ServiceAccount" and item["metadata"]["name"] in ("default", "helm-controller", "kustomize-controller", "notification-controller", "source-controller"):
            continue
        if namespace and namespace not in bundle["namespaces"]:
            raise ValueError("Object outside reviewed namespace scope")
        try:
            command(["kubectl", "--context", target, "apply", "--server-side", "--field-manager=envplane-cni-migration", "-f", "-"], json.dumps(item).encode())
        except ValueError as exc:
            raise ValueError("Reviewed object rejected: " + item["kind"] + "/" + (namespace or "cluster") + "/" + item["metadata"]["name"]) from exc
    print(json.dumps({"restoredConfiguration": True, "workloadsStopped": True, "fluxSuspended": True, "target": target}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("snapshot", "restore"))
    parser.add_argument("--source")
    parser.add_argument("--target", required=True)
    parser.add_argument("--namespace", action="append")
    parser.add_argument("--recipient", default="")
    parser.add_argument("--archive", required=True)
    parser.add_argument("--archive-sha256")
    parser.add_argument("--identity")
    parser.add_argument("--approve-target")
    args = parser.parse_args()
    try:
        if args.mode == "snapshot":
            snapshot(args.source, args.target, args.namespace, args.recipient, args.archive)
        else:
            restore(args.archive, args.archive_sha256, args.identity, args.target, args.approve_target)
    except ValueError as exc:
        print(str(exc) + "; no credentials printed", file=sys.stderr)
        sys.exit(1)
    except (KeyError, TypeError, OSError):
        print("Scoped encrypted configuration operation rejected; no credentials printed", file=sys.stderr)
        sys.exit(1)
