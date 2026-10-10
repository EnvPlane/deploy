#!/usr/bin/env python3
"""Explicitly authorized, fixture-only live verification and bounded onboarding.

plan is read-only to Kubernetes. prepare/run/cleanup require exact run approval.
All evidence is metadata/hash only, never existing volume bytes or credentials.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import struct
import subprocess
import tempfile
import time

CONTEXT = "kind-envplane-readiness-682"
LABEL = "envplane.io/pvc-copy-live-run"
PREFIX = "pvccopy-live-"
PAYLOAD_BYTES = 1024 * 1024
CLAIMS = {"source", "uid-probe", "copy-positive", "copy-cancel", "copy-uid"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def save(path, obj):
    path = Path(path)
    require(not path.is_symlink(), "refuse symlink evidence")
    fd, temporary = tempfile.mkstemp(prefix=".pvc-live-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(obj, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def validate(ledger):
    run_id = ledger.get("runID", "")
    require(re.fullmatch(r"[a-f0-9]{16}", run_id), "invalid fixture run ID")
    require(ledger["context"] == CONTEXT, "unexpected cluster context")
    require(ledger["sourceNamespace"] == f"{PREFIX}{run_id}-src" and
            ledger["targetNamespace"] == f"{PREFIX}{run_id}-dst", "fixture scope mismatch")
    require(re.fullmatch(r"[a-z0-9./:_-]+@sha256:[a-f0-9]{64}", ledger["image"]), "helper must be digest pinned")
    require(ledger.get("clusterUID"), "missing isolated cluster identity")
    require(re.fullmatch(r"[a-f0-9]{64}", ledger.get("helperBinarySHA256", "")), "matching helper binary SHA256 required")
    return ledger


def approval(ledger, authorized):
    validate(ledger)
    require(authorized == ledger["runID"], "explicit exact fixture authorization required")


class Cluster:
    def __init__(self, ledger):
        self.ledger = validate(ledger)

    def call(self, args, obj=None):
        command = ["kubectl", "--kubeconfig", self.ledger["kubeconfig"], "--context", CONTEXT,
                   "--request-timeout=30s", *args]
        result = subprocess.run(command, input=None if obj is None else json.dumps(obj),
                                text=True, capture_output=True, timeout=90, check=False)
        journal = self.ledger.get("commandJournal")
        if journal:
            entry = {"command": command, "request": obj, "returnCode": result.returncode}
            # Only fixture/Kubernetes metadata; never arbitrary stderr, credentials
            # or archive payload. This harness does not exec or read Secrets.
            if result.returncode == 0 and result.stdout.strip():
                entry["response"] = json.loads(result.stdout)
            with open(journal, "a", encoding="utf-8") as output:
                output.write(json.dumps(entry, sort_keys=True) + "\n")
        require(result.returncode == 0, f"kubectl {args[0]} failed (no arbitrary API output retained)")
        return json.loads(result.stdout) if result.stdout.strip() else None

    def get(self, kind, name, namespace=None, absent=False):
        args = ["get", kind, name, "-o", "json"]
        if namespace:
            require(namespace in (self.ledger["sourceNamespace"], self.ledger["targetNamespace"]), "namespace outside fixture")
            args += ["-n", namespace]
        if absent:
            args += ["--ignore-not-found"]
        return self.call(args)

    def identity(self):
        require(self.get("namespace", "kube-system")["metadata"]["uid"] == self.ledger["clusterUID"], "cluster UID changed")

    def namespace(self, name):
        require(name in (self.ledger["sourceNamespace"], self.ledger["targetNamespace"]), "unowned namespace")
        obj = self.get("namespace", name)
        meta = obj["metadata"]
        require(meta.get("uid") == self.ledger["namespaceUIDs"].get(name) and
                meta.get("labels", {}).get(LABEL) == self.ledger["runID"] and
                not meta.get("deletionTimestamp"), "fixture namespace UID/ownership changed")
        return obj

    def create(self, obj):
        meta = obj["metadata"]
        namespace = meta.get("namespace")
        if namespace:
            self.namespace(namespace)
        else:
            if obj["kind"] == "Namespace":
                require(meta["name"] in (self.ledger["sourceNamespace"], self.ledger["targetNamespace"]), "nonfixture namespace create")
            else:
                require(f"{obj['kind']}/{meta['name']}" in self.ledger.get("clusterObjectUIDs", {}), "unapproved cluster-scoped object")
                if obj["kind"] == "ClusterRole":
                    require(all(rule.get("verbs") == ["get"] and rule.get("resourceNames") and
                                "*" not in json.dumps(rule) for rule in obj["rules"]), "broad cluster grant refused")
        require(meta.get("labels", {}).get(LABEL) == self.ledger["runID"], "creation lacks fixture ownership")
        args = ["create", "-f", "-", "-o", "json"]
        if namespace:
            args += ["-n", namespace]
        return self.call(args, obj)

    def delete(self, kind, name, namespace=None):
        # UID + resourceVersion preconditions prevent name-replacement deletion.
        if kind == "namespace":
            obj = self.namespace(name)
        else:
            self.namespace(namespace)
            require(kind in ("pods", "persistentvolumeclaims"), "unsupported cleanup kind")
            obj = self.get(kind, name, namespace)
            require(obj["metadata"].get("uid") == self.ledger["objectUIDs"].get(f"{namespace}/{kind}/{name}"), "unknown fixture object UID")
        meta = obj["metadata"]
        path = f"/api/v1/namespaces/{name}" if kind == "namespace" else f"/api/v1/namespaces/{namespace}/{kind}/{name}"
        self.call(["delete", "--raw", path, "-f", "-"], {"apiVersion": "v1", "kind": "DeleteOptions",
            "preconditions": {"uid": meta["uid"], "resourceVersion": meta["resourceVersion"]}, "propagationPolicy": "Foreground"})

    def idle(self, namespace):
        self.namespace(namespace)
        pods = self.call(["get", "pods", "-n", namespace, "-o", "json", "--chunk-size=0"])
        require(not pods.get("metadata", {}).get("continue"), "incomplete fixture pod listing")
        require(not pods["items"], "fixture helpers or consumers remain; do not continue")
        for kind in ("deployments", "statefulsets", "replicasets", "daemonsets", "jobs", "cronjobs"):
            objects = self.call(["get", kind, "-n", namespace, "-o", "json", "--chunk-size=0"])
            require(not objects.get("metadata", {}).get("continue") and not objects["items"], "fixture controller inventory not empty")
        return {"pods": 0, "controllers": 0, "readOnlyAudit": True}


def own_meta(ledger, name, namespace=None):
    meta = {"name": name, "labels": {LABEL: ledger["runID"], "envplane.io/environment-class": "test"}}
    if namespace:
        meta["namespace"] = namespace
    return meta


def claim(ledger, name):
    return {"apiVersion": "v1", "kind": "PersistentVolumeClaim",
            "metadata": {**own_meta(ledger, name, ledger["sourceNamespace"]), "annotations": {"envplane.io/pvc-copy-offline": "true"}},
            "spec": {"storageClassName": ledger["storageClass"], "volumeMode": "Filesystem",
                     "accessModes": ["ReadWriteOnce"], "resources": {"requests": {"storage": "64Mi"}}}}


def seed_pod(ledger):
    # Only this owned fixture initializer is writable. No fsGroup/SELinux trick.
    marker = f"envplane-pvc-copy-live-{ledger['runID']}"
    script = "set -eu; " + "; ".join(
        f"mkdir -p {root}/payload; printf '%s\\n' '{marker}' > {root}/marker.txt; "
        f"dd if=/dev/zero of={root}/payload/bytes.bin bs=1024 count=1024; "
        f"chown -R 1000:2000 {root}; chmod 0770 {root}; chmod 0750 {root}/payload; "
        f"chmod 0640 {root}/marker.txt; chmod 0600 {root}/payload/bytes.bin"
        for root in ("/fixture", "/uid-probe"))
    return {"apiVersion": "v1", "kind": "Pod", "metadata": own_meta(ledger, "fixture-seed", ledger["sourceNamespace"]),
            "spec": {"serviceAccountName": "default", "automountServiceAccountToken": False,
                     "restartPolicy": "Never", "activeDeadlineSeconds": 180,
                     "securityContext": {"runAsUser": 0, "runAsGroup": 0, "seccompProfile": {"type": "RuntimeDefault"}},
                     "containers": [{"name": "seed", "image": ledger["image"], "command": ["sh", "-c", script],
                         "securityContext": {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True,
                             "capabilities": {"drop": ["ALL"], "add": ["DAC_OVERRIDE", "CHOWN", "FOWNER"]}},
                         "resources": {"requests": {"cpu": "10m", "memory": "32Mi"}, "limits": {"cpu": "1", "memory": "128Mi"}},
                         "volumeMounts": [{"name": "source", "mountPath": "/fixture"}, {"name": "uid-probe", "mountPath": "/uid-probe"}]}],
                     "volumes": [{"name": name, "persistentVolumeClaim": {"claimName": name}} for name in ("source", "uid-probe")]}}


def expected_receipt(run_id):
    marker = f"envplane-pvc-copy-live-{run_id}\n".encode()
    entries = [(".", b"5", 0o770, b""), ("marker.txt", b"0", 0o640, marker),
               ("payload", b"5", 0o750, b""), ("payload/bytes.bin", b"0", 0o600, bytes(PAYLOAD_BYTES))]
    digest = hashlib.sha256()
    for name, kind, mode, data in entries:
        raw_name = name.encode()
        digest.update(struct.pack(">I", len(raw_name)) + raw_name + kind + struct.pack(">qqqq", len(data), mode, 1000, 2000))
        digest.update(data)
    return {"root": {"uid": 1000, "gid": 2000, "mode": 0o770}, "bytes": PAYLOAD_BYTES + len(marker),
            "entries": len(entries), "sha256": digest.hexdigest()}


def driver_config(ledger, mode, source="source", target="copy-positive"):
    require(source in ("source", "uid-probe") and target in CLAIMS and target.startswith("copy-"), "invalid case")
    return {"runID": ledger["runID"], "kubeconfig": ledger["kubeconfig"], "context": ledger["context"],
            "clusterUID": ledger["clusterUID"], "sourceUID": ledger["sourceUIDs"][source], "sourceName": source,
            "sourceNamespaceUID": ledger["namespaceUIDs"][ledger["sourceNamespace"]],
            "targetNamespaceUID": ledger["namespaceUIDs"][ledger["targetNamespace"]],
            "targetName": target, "storageClass": ledger["storageClass"], "image": ledger["image"],
            "commandJournal": str(Path(ledger.get("commandJournal", "/private/tmp/pvc-live-commands.jsonl")).with_suffix(".driver.jsonl")),
            "helperBinarySHA256": ledger["helperBinarySHA256"], "mode": mode}


def invoke(binary, config):
    result = subprocess.run([str(Path(binary).resolve())], input=json.dumps(config), text=True,
                            capture_output=True, timeout=190, check=False)
    message = "driver refused or failed; evidence remains NOT PASSED"
    if result.stderr.startswith("fixture driver refused:"):
        message = result.stderr.strip()[:4096]
    require(result.returncode == 0, message)
    response = json.loads(result.stdout)
    require(response.get("mode") == config["mode"], "unexpected driver response")
    return response


def remember(ledger, obj, kind):
    meta = obj["metadata"]
    ledger["objectUIDs"][f"{meta['namespace']}/{kind}/{meta['name']}"] = meta["uid"]


def record_volume(cluster, ledger, claim_obj):
    """Inspect only the dynamically allocated PV of an exact owned fixture UID."""
    meta = claim_obj["metadata"]
    name = claim_obj.get("spec", {}).get("volumeName")
    if not name:
        return
    # This isolated harness is for the discovered local-path standard driver.
    require(name == "pvc-" + meta["uid"], "unexpected fixture PV naming/binding")
    volume = cluster.get("pv", name)
    ref = volume["spec"]["claimRef"]
    require(ref["uid"] == meta["uid"] and ref["namespace"] == meta["namespace"] and ref["name"] == meta["name"], "PV claim identity is not our fixture")
    ledger.setdefault("fixtureVolumes", {})[name] = {"uid": volume["metadata"]["uid"], "claimUID": meta["uid"]}


def prepare(ledger, args):
    approval(ledger, args.authorize_fixture)
    require(ledger["stage"] == "planned", "prepare cannot adopt/retry unknown fixture")
    cluster = Cluster(ledger)
    cluster.identity()
    # Check BOTH collisions before the first write; never apply/adopt.
    for name in (ledger["sourceNamespace"], ledger["targetNamespace"]):
        require(cluster.get("namespace", name, absent=True) is None, "fixture namespace already exists")
    for name in (ledger["sourceNamespace"], ledger["targetNamespace"]):
        obj = cluster.create({"apiVersion": "v1", "kind": "Namespace", "metadata": own_meta(ledger, name)})
        ledger["namespaceUIDs"][name] = obj["metadata"]["uid"]
        ledger["stage"] = "preparing"
        save(args.ledger, ledger)
    for name in ("source", "uid-probe"):
        obj = cluster.create(claim(ledger, name));remember(ledger, obj, "persistentvolumeclaims")
        ledger["sourceUIDs"][name] = obj["metadata"]["uid"]
        save(args.ledger, ledger)
    obj = cluster.create(seed_pod(ledger));remember(ledger, obj, "pods");save(args.ledger, ledger)
    deadline = time.monotonic() + 180
    while True:
        obj = cluster.get("pod", "fixture-seed", ledger["sourceNamespace"])
        phase = obj.get("status", {}).get("phase")
        require(phase != "Failed" and time.monotonic() < deadline, "fixture initialization failed; retained for scoped cleanup")
        if phase == "Succeeded":
            break
        time.sleep(1)
    cluster.delete("pods", "fixture-seed", ledger["sourceNamespace"])
    wait_absent(cluster, "pod", "fixture-seed", ledger["sourceNamespace"])
    for name in ("source", "uid-probe"):
        obj = cluster.get("pvc", name, ledger["sourceNamespace"])
        require(obj["metadata"]["uid"] == ledger["sourceUIDs"][name] and obj.get("status", {}).get("phase") == "Bound", "fixture source not bound")
        ledger.setdefault("sourceVolumes", {})[name] = obj["spec"]["volumeName"]
        record_volume(cluster, ledger, obj)
    ledger["sourceIdleBeforeOnboarding"] = cluster.idle(ledger["sourceNamespace"])
    ledger["expectedReceipt"] = expected_receipt(ledger["runID"])
    ledger["stage"] = "prepared"
    save(args.ledger, ledger)
    preview = invoke(args.driver, driver_config(ledger, "compile"))
    save(Path(args.ledger).with_suffix(".onboarding-preview.json"), preview)
    return {"prepared": True, "liveCopy": "NOT RUN", "runID": ledger["runID"], "principal": f"system:serviceaccount:{ledger['targetNamespace']}:copy-runner"}


def wait_absent(cluster, kind, name, namespace=None):
    deadline = time.monotonic() + 120
    while cluster.get(kind, name, namespace, absent=True) is not None:
        require(time.monotonic() < deadline, "object deletion not confirmed")
        time.sleep(1)


CLUSTER_KINDS = {
    "ValidatingAdmissionPolicyBinding": ("validatingadmissionpolicybinding", "admissionregistration.k8s.io/v1/validatingadmissionpolicybindings"),
    "ValidatingAdmissionPolicy": ("validatingadmissionpolicy", "admissionregistration.k8s.io/v1/validatingadmissionpolicies"),
    "ClusterRoleBinding": ("clusterrolebinding", "rbac.authorization.k8s.io/v1/clusterrolebindings"),
    "ClusterRole": ("clusterrole", "rbac.authorization.k8s.io/v1/clusterroles"),
}


def onboarding_manifests(ledger, preview):
    source, target, run_id = ledger["sourceNamespace"], ledger["targetNamespace"], ledger["runID"]
    source_helper = preview["sourceHelperName"]
    fence = preview["fencePreview"]
    fence_name = fence[0]["metadata"]["name"]
    rules_source = [
        {"apiGroups": [""], "resources": ["persistentvolumeclaims"], "resourceNames": ["source", "uid-probe"], "verbs": ["get"]},
        {"apiGroups": [""], "resources": ["pods"], "verbs": ["get", "list", "create"]},
        {"apiGroups": [""], "resources": ["pods", "pods/exec"], "resourceNames": [source_helper], "verbs": ["delete", "create"]},
        {"apiGroups": ["apps"], "resources": ["deployments", "statefulsets", "replicasets", "daemonsets"], "verbs": ["list"]},
        {"apiGroups": ["batch"], "resources": ["jobs", "cronjobs"], "verbs": ["list"]}]
    rules_target = [
        {"apiGroups": [""], "resources": ["persistentvolumeclaims"], "verbs": ["get", "list", "create"]},
        {"apiGroups": [""], "resources": ["pods"], "verbs": ["get", "list", "create", "delete"]},
        {"apiGroups": [""], "resources": ["pods/exec"], "verbs": ["create"]}]
    manifests = [{"apiVersion": "v1", "kind": "ServiceAccount", "metadata": own_meta(ledger, "copy-runner", target), "automountServiceAccountToken": False}]
    for namespace, rules in ((source, rules_source), (target, rules_target)):
        manifests.extend([
            {"apiVersion": "rbac.authorization.k8s.io/v1", "kind": "Role", "metadata": own_meta(ledger, "copy-fixture", namespace), "rules": rules},
            {"apiVersion": "rbac.authorization.k8s.io/v1", "kind": "RoleBinding", "metadata": own_meta(ledger, "copy-fixture", namespace),
             "roleRef": {"apiGroup": "rbac.authorization.k8s.io", "kind": "Role", "name": "copy-fixture"},
             "subjects": [{"kind": "ServiceAccount", "namespace": target, "name": "copy-runner"}]}])
    reader = f"{PREFIX}{run_id}-reader"
    manifests.extend([
        {"apiVersion": "rbac.authorization.k8s.io/v1", "kind": "ClusterRole", "metadata": own_meta(ledger, reader), "rules": [
            {"apiGroups": [""], "resources": ["namespaces"], "resourceNames": ["kube-system", source, target], "verbs": ["get"]},
            {"apiGroups": ["admissionregistration.k8s.io"], "resources": ["validatingadmissionpolicies", "validatingadmissionpolicybindings"], "resourceNames": [fence_name], "verbs": ["get"]}]},
        {"apiVersion": "rbac.authorization.k8s.io/v1", "kind": "ClusterRoleBinding", "metadata": own_meta(ledger, reader),
         "roleRef": {"apiGroup": "rbac.authorization.k8s.io", "kind": "ClusterRole", "name": reader},
         "subjects": [{"kind": "ServiceAccount", "namespace": target, "name": "copy-runner"}]}])
    for manifest in fence:
        manifest["metadata"]["labels"] = {LABEL: run_id}
        manifests.append(manifest)
    return manifests


def onboard(ledger, args):
    approval(ledger, args.authorize_fixture)
    require(ledger["stage"] == "prepared", "prepare fixture before onboarding")
    build = json.loads(Path(args.build_record).read_text())
    require(build.get("archiveBinaryVerified") is True and build["image"] == ledger["image"] and
            build["helperBinarySHA256"] == ledger["helperBinarySHA256"] and build["runID"] == ledger["runID"], "matching local helper build not verified")
    cluster = Cluster(ledger);cluster.identity()
    cluster.idle(ledger["sourceNamespace"]);cluster.idle(ledger["targetNamespace"])
    preview = invoke(args.driver, driver_config(ledger, "compile"))
    manifests = onboarding_manifests(ledger, preview)
    ledger["clusterObjectUIDs"] = {}
    for manifest in manifests:
        meta = manifest["metadata"]
        kind = manifest["kind"]
        require(cluster.get(CLUSTER_KINDS[kind][0] if kind in CLUSTER_KINDS else kind.lower(),
                            meta["name"], meta.get("namespace"), absent=True) is None, "onboarding name already exists; never adopt")
        if kind in CLUSTER_KINDS:
            ledger["clusterObjectUIDs"][f"{kind}/{meta['name']}"] = None
    # Persist collision-free exact targets before the first grant/policy write.
    ledger["onboardingManifestSHA256"] = hashlib.sha256(json.dumps(manifests, sort_keys=True).encode()).hexdigest()
    save(args.ledger, ledger)
    for manifest in manifests:
        obj = cluster.create(manifest);meta = obj["metadata"]
        if manifest["kind"] in CLUSTER_KINDS:
            ledger["clusterObjectUIDs"][f"{manifest['kind']}/{meta['name']}"] = meta["uid"]
        else:
            remember(ledger, obj, manifest["kind"].lower())
        save(args.ledger, ledger)
    fence_name = preview["fencePreview"][0]["metadata"]["name"]
    deadline = time.monotonic() + 90
    while True:
        policy = cluster.get("validatingadmissionpolicy", fence_name)
        status = policy.get("status", {})
        require(time.monotonic() < deadline, "policy current-generation type check timed out")
        if status.get("observedGeneration") == policy["metadata"]["generation"] and "typeChecking" in status:
            require(not status["typeChecking"].get("expressionWarnings"), "policy CEL type warnings")
            break
        time.sleep(1)
    ledger["policyTypeCheck"] = {"uid": policy["metadata"]["uid"], "generation": policy["metadata"]["generation"], "status": status}
    review = {key: ledger[key] for key in ("runID", "clusterUID", "image", "namespaceUIDs", "sourceUIDs", "helperBinarySHA256")}
    review.update({"allowRootHelpers": True, "fixtureExecutionApproved": True, "matchingHelperBuildVerified": True,
                   "principal": f"system:serviceaccount:{ledger['targetNamespace']}:copy-runner",
                   "authorization": "explicit user greenlight for isolated fixture-only verification",
                   "onboardingManifestSHA256": ledger["onboardingManifestSHA256"]})
    review_path = Path(args.ledger).with_suffix(".review.json");save(review_path, review)
    ledger["reviewPath"] = str(review_path);save(args.ledger, ledger)
    return {"onboarding": "fixture-only resources created; CEL current-generation type check passed",
            "review": str(review_path), "liveCopy": "NOT RUN", "negativeProbes": "required by each driver call"}


def refresh_fence(ledger, args):
    """Refresh only our exact UID-bound policy after its owner fixes Runner code."""
    approval(ledger, args.authorize_fixture)
    require(ledger["stage"] in ("prepared", "running") and not ledger.get("liveResults"), "refresh allowed only before payload execution")
    cluster = Cluster(ledger);cluster.identity()
    cluster.idle(ledger["sourceNamespace"]);cluster.idle(ledger["targetNamespace"])
    for name in ("copy-positive", "copy-cancel", "copy-uid"):
        require(cluster.get("pvc", name, ledger["targetNamespace"], absent=True) is None, "refresh cannot adopt existing targets")
    preview = invoke(args.driver, driver_config(ledger, "compile"))
    manifest = preview["fencePreview"][0]
    name = manifest["metadata"]["name"]
    policy = cluster.get("validatingadmissionpolicy", name)
    meta = policy["metadata"]
    require(meta["uid"] == ledger["clusterObjectUIDs"].get(f"ValidatingAdmissionPolicy/{name}") and
            meta.get("labels", {}).get(LABEL) == ledger["runID"] and
            meta["annotations"] == manifest["metadata"]["annotations"], "policy source authority/ownership changed")
    operations = [{"op": "test", "path": "/metadata/uid", "value": meta["uid"]},
                  {"op": "test", "path": "/metadata/resourceVersion", "value": meta["resourceVersion"]},
                  {"op": "replace", "path": "/spec", "value": manifest["spec"]}]
    # kubectl patch -p is metadata-only, containing the reviewed source policy.
    cluster.call(["patch", "validatingadmissionpolicy", name, "--type=json", "-p", json.dumps(operations), "-o", "json"])
    deadline = time.monotonic() + 90
    while True:
        policy = cluster.get("validatingadmissionpolicy", name)
        status = policy.get("status", {})
        require(time.monotonic() < deadline, "refreshed policy type check timed out")
        if status.get("observedGeneration") == policy["metadata"]["generation"] and "typeChecking" in status:
            require(not status["typeChecking"].get("expressionWarnings"), "refreshed policy CEL warnings")
            break
        time.sleep(1)
    ledger["policyTypeCheck"] = {"uid": policy["metadata"]["uid"], "generation": policy["metadata"]["generation"], "status": status}
    save(args.ledger, ledger)
    return {"policyUID": meta["uid"], "generation": policy["metadata"]["generation"], "payloadExecution": "NOT RUN"}


def reviewed(ledger, path):
    require(path, "main's reviewed onboarding record required")
    review = json.loads(Path(path).read_text())
    for field in ("runID", "clusterUID", "image", "namespaceUIDs", "sourceUIDs", "helperBinarySHA256"):
        require(review.get(field) == ledger[field], f"review scope mismatch: {field}")
    require(review.get("allowRootHelpers") is True and review.get("fixtureExecutionApproved") is True,
            "fixture root/execution approval missing")
    require(review.get("principal") == f"system:serviceaccount:{ledger['targetNamespace']}:copy-runner", "review principal mismatch")
    require(review.get("matchingHelperBuildVerified") is True and review.get("helperBinarySHA256"), "matching host/helper binary proof required")
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_cases(ledger, args):
    approval(ledger, args.authorize_fixture)
    resume = getattr(args, "retry_preflight_only", False) and ledger["stage"] == "running" and not ledger.get("liveResults")
    require(ledger["stage"] == "prepared" or resume, "fixture must be prepared; failed runs require operator review")
    ledger["reviewSHA256"] = reviewed(ledger, args.reviewed_onboarding)
    cluster = Cluster(ledger);cluster.identity()
    cluster.namespace(ledger["sourceNamespace"]);cluster.namespace(ledger["targetNamespace"])
    cluster.idle(ledger["sourceNamespace"]);cluster.idle(ledger["targetNamespace"])
    if resume:
        for name in ("copy-positive", "copy-cancel", "copy-uid"):
            require(cluster.get("pvc", name, ledger["targetNamespace"], absent=True) is None, "preflight retry cannot adopt targets")
    ledger["stage"] = "running";ledger["liveResults"] = {};save(args.ledger, ledger)
    results = ledger["liveResults"]

    def case(name, mode, target="copy-positive", source="source"):
        response = invoke(args.driver, driver_config(ledger, mode, source, target))
        require(response.get("live") is True, "nonlive driver result cannot satisfy live case")
        results[name] = response;save(args.ledger, ledger)
        obj = cluster.get("pvc", target, ledger["targetNamespace"], absent=True)
        if obj:
            require(obj["metadata"].get("annotations", {}).get("envplane.io/pvc-copy-plan") == response["plan"]["digest"], "target plan identity mismatch")
            remember(ledger, obj, "persistentvolumeclaims");save(args.ledger, ledger)
            record_volume(cluster, ledger, obj);save(args.ledger, ledger)
        return response

    before = case("sourceBefore", "audit-source")["value"]
    require(before == ledger["expectedReceipt"], "source marker/bytes/numeric/root metadata mismatch")
    positive = case("positive", "execute")
    require(positive.get("outcome") == "complete" and len(positive.get("markers", [])) == 1, "live copy failed")
    marker = positive["markers"][0]
    require(marker["receipt"] == before and marker["sourceUID"] == ledger["sourceUIDs"]["source"] and
            marker["immutablePlanDigest"] == positive["plan"]["digest"], "completion receipt mismatch")
    retry = case("completedRetry", "execute")
    require(retry.get("outcome") == "complete" and retry["markers"] == [marker], "durable idempotent retry failed")
    # New read-only helper after copy helpers are deleted proves remount persistence.
    persisted = case("remountedTarget", "audit-target")["value"]
    require(persisted == marker, "target remount/rehash mismatch")
    cancelled = case("cancelledImport", "cancel", "copy-cancel")
    require(cancelled.get("outcome") == "cancelled" and cancelled.get("interruptedAfterBytes") == 8192 and
            not cancelled.get("markers"), "real streaming cancellation not proven")
    case("cancelledState", "inspect-partial", "copy-cancel")
    partial = case("partialRetryRefused", "execute", "copy-cancel")
    require(partial.get("outcome") == "partial_target" and not partial.get("markers"), "partial target was not refused")

    # Actual UID drift on the separate, owned, never-copied probe claim only.
    old_uid = ledger["sourceUIDs"]["uid-probe"]
    cluster.delete("persistentvolumeclaims", "uid-probe", ledger["sourceNamespace"])
    wait_absent(cluster, "pvc", "uid-probe", ledger["sourceNamespace"])
    replacement = cluster.create(claim(ledger, "uid-probe"));remember(ledger, replacement, "persistentvolumeclaims")
    new_uid = replacement["metadata"]["uid"]
    require(new_uid != old_uid, "source probe UID did not drift")
    ledger["uidProbeReplacement"] = {"oldUID": old_uid, "newUID": new_uid};save(args.ledger, ledger)
    drift = case("sourceUIDDriftRefused", "execute", "copy-uid", "uid-probe")
    require(drift.get("outcome") == "unsafe" and not drift.get("markers") and
            cluster.get("pvc", "copy-uid", ledger["targetNamespace"], absent=True) is None,
            "stale source UID was not refused before target creation")
    after = case("sourceAfter", "audit-source")["value"]
    require(after == before, "source filesystem preservation failed")
    source = cluster.get("pvc", "source", ledger["sourceNamespace"])
    require(source["metadata"]["uid"] == ledger["sourceUIDs"]["source"] and
            source["spec"]["volumeName"] == ledger["sourceVolumes"]["source"] and
            source["metadata"]["annotations"]["envplane.io/pvc-copy-offline"] == "true", "source PVC identity/maintenance drift")
    ledger["sourceIdleAfter"] = cluster.idle(ledger["sourceNamespace"])
    ledger["targetIdleAfter"] = cluster.idle(ledger["targetNamespace"])
    ledger["stage"] = "live-passed";save(args.ledger, ledger)
    return {"liveFilesystemCases": "PASS", "cleanup": "PENDING", "runtimeReady": "NOT ASSERTED", "mysql": "NOT RUN"}


def cleanup(ledger, args):
    approval(ledger, args.authorize_fixture)
    cluster = Cluster(ledger);cluster.identity()
    # Never sweep by label. Refuse foreign content even within an owned namespace.
    for namespace in (ledger["targetNamespace"], ledger["sourceNamespace"]):
        if namespace not in ledger["namespaceUIDs"]:
            continue
        if cluster.get("namespace", namespace, absent=True) is None:
            continue
        cluster.namespace(namespace)
        if namespace == ledger["sourceNamespace"]:
            seeder = cluster.get("pod", "fixture-seed", namespace, absent=True)
            if seeder:
                cluster.delete("pods", "fixture-seed", namespace)
                wait_absent(cluster, "pod", "fixture-seed", namespace)
        cluster.idle(namespace)
        pvcs = cluster.call(["get", "pvc", "-n", namespace, "-o", "json", "--chunk-size=0"])
        require(not pvcs.get("metadata", {}).get("continue"), "incomplete cleanup inventory")
        for obj in pvcs["items"]:
            name = obj["metadata"]["name"]
            require(name in ("source", "uid-probe") if namespace == ledger["sourceNamespace"] else name in ("copy-positive", "copy-cancel", "copy-uid"), "foreign claim in fixture namespace")
            if namespace == ledger["sourceNamespace"]:
                require(obj["metadata"]["uid"] == ledger["objectUIDs"].get(f"{namespace}/persistentvolumeclaims/{name}"), "source fixture replacement unknown")
            else:
                require(obj["metadata"].get("annotations", {}).get("envplane.io/project") == f"{PREFIX}{ledger['runID']}" and
                        obj["metadata"]["uid"] == ledger["objectUIDs"].get(f"{namespace}/persistentvolumeclaims/{name}"), "target copy ownership/UID mismatch")
            record_volume(cluster, ledger, obj)
        save(args.ledger, ledger)
        # Namespace teardown also removes fixture-only reviewed RBAC/SA. Require
        # main to attest exclusivity; externally installed policies stay untouched.
        require(args.confirm_exclusive_namespaces == ledger["runID"], "explicit exclusive-namespace cleanup approval required")
        cluster.delete("namespace", namespace)
        wait_absent(cluster, "namespace", namespace)
    # Delete only recorded exact cluster-scoped fixture resources, with UID/RV.
    for kind in CLUSTER_KINDS:
        for key, uid in ledger.get("clusterObjectUIDs", {}).items():
            object_kind, name = key.split("/", 1)
            if object_kind != kind:
                continue
            require(uid, "unconfirmed cluster create outcome requires operator review")
            api_kind, resource_path = CLUSTER_KINDS[kind]
            obj = cluster.get(api_kind, name, absent=True)
            if obj is None:
                continue
            meta = obj["metadata"]
            require(meta["uid"] == uid and meta.get("labels", {}).get(LABEL) == ledger["runID"], "cluster object ownership changed")
            cluster.call(["delete", "--raw", f"/apis/{resource_path}/{name}", "-f", "-"],
                         {"apiVersion": "v1", "kind": "DeleteOptions", "preconditions": {"uid": uid, "resourceVersion": meta["resourceVersion"]}})
            wait_absent(cluster, api_kind, name)
    for name, expected in ledger.get("fixtureVolumes", {}).items():
        deadline = time.monotonic() + 120
        while True:
            volume = cluster.get("pv", name, absent=True)
            if volume is None:
                break
            require(volume["metadata"]["uid"] == expected["uid"] and
                    volume["spec"]["claimRef"]["uid"] == expected["claimUID"], "fixture PV replaced during cleanup")
            require(time.monotonic() < deadline, "fixture PV reclamation not confirmed; no manual PV deletion")
            time.sleep(1)
    ledger["stage"] = "cleaned";ledger["cleanup"] = "fixture namespace and recorded exact policy/RBAC deletion confirmed"
    save(args.ledger, ledger)
    return {"cleanup": "CONFIRMED", "externalPolicies": "not touched"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("plan", "prepare", "onboard", "refresh-fence", "run", "cleanup"))
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--kubeconfig")
    parser.add_argument("--image")
    parser.add_argument("--helper-binary-sha256")
    parser.add_argument("--run-id")
    parser.add_argument("--storage-class", default="standard")
    parser.add_argument("--driver")
    parser.add_argument("--build-record")
    parser.add_argument("--authorize-fixture")
    parser.add_argument("--reviewed-onboarding")
    parser.add_argument("--confirm-exclusive-namespaces")
    parser.add_argument("--retry-preflight-only", action="store_true", help="retry only a failed, idle, target-free preflight")
    args = parser.parse_args()
    if args.action == "plan":
        require(args.kubeconfig and args.image, "explicit kubeconfig and matching-helper image required")
        require(not Path(args.ledger).exists(), "refuse existing ledger")
        run_id = args.run_id or secrets.token_hex(8)
        ledger = {"runID": run_id, "kubeconfig": str(Path(args.kubeconfig).resolve()), "context": CONTEXT,
                  "clusterUID": "discovery-pending", "image": args.image, "helperBinarySHA256": args.helper_binary_sha256,
                  "storageClass": args.storage_class,
                  "sourceNamespace": f"{PREFIX}{run_id}-src", "targetNamespace": f"{PREFIX}{run_id}-dst",
                  "stage": "planned", "namespaceUIDs": {}, "objectUIDs": {}, "sourceUIDs": {},
                  "commandJournal": str(Path(args.ledger).with_suffix(".commands.jsonl").resolve())}
        # Journal exists with private mode before any API observation is logged.
        fd = os.open(ledger["commandJournal"], os.O_CREAT|os.O_EXCL|os.O_WRONLY, 0o600)
        os.close(fd)
        cluster = Cluster(ledger)
        ledger["clusterUID"] = cluster.get("namespace", "kube-system")["metadata"]["uid"]
        validate(ledger);save(args.ledger, ledger)
        result = {"writesToCluster": 0, "ledger": args.ledger, "namespaces": [ledger["sourceNamespace"], ledger["targetNamespace"]],
                  "copyPrincipal": f"system:serviceaccount:{ledger['targetNamespace']}:copy-runner",
                  "fixtureHelperPrincipals": [f"system:serviceaccount:{ns}:default" for ns in (ledger["sourceNamespace"], ledger["targetNamespace"])]}
    else:
        ledger = validate(json.loads(Path(args.ledger).read_text()))
        if args.action in ("prepare", "onboard", "refresh-fence", "run"):
            require(args.driver and Path(args.driver).is_file(), "host-built driver required")
        if args.action == "onboard":
            require(args.build_record, "verified local build record required")
        result = {"prepare": prepare, "onboard": onboard, "refresh-fence": refresh_fence, "run": run_cases, "cleanup": cleanup}[args.action](ledger, args)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        raise SystemExit(f"PVC-copy fixture stopped: {error}") from error
