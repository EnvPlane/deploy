#!/usr/bin/env python3
"""Scoped encrypted backup/rehearsal primitive; never freezes or cuts over.

All live transfer requires a parent-approved plan hash and explicit operation
gate. Inventory alone is read-only. Secrets/kubeconfigs are never collected.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def read_json_command(args):
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        raise ValueError("Read-only inventory command failed")
    return json.loads(result.stdout)


def get(context, kind, namespace=None):
    args = ["kubectl", "--context", context, "--request-timeout=30s", "get", kind]
    if namespace:
        args += ["-n", namespace]
    return read_json_command(args + ["-o", "json"])


def ref(item):
    meta = item["metadata"]
    return {key: meta[key] for key in ("name", "namespace", "uid") if key in meta}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def file_digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def write_private(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(value, handle, indent=2)
        handle.write("\n")


def inventory(source, target, namespaces):
    if source == target or not namespaces or len(namespaces) != len(set(namespaces)):
        raise ValueError("Distinct contexts and unique exact namespace allowlist required")
    if any(not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,61}[a-z0-9]", name) for name in namespaces):
        raise ValueError("Exact namespace names required, no glob or empty scope")
    plan = {"schemaVersion": 1, "source": source, "target": target,
            "sourceUID": get(source, "namespace/kube-system")["metadata"]["uid"],
            "targetUID": get(target, "namespace/kube-system")["metadata"]["uid"],
            "namespaces": [], "flux": [], "cutover": "external parent-coordinated only"}
    if plan["sourceUID"] == plan["targetUID"]:
        raise ValueError("Source and target resolve to the same cluster")
    for name in namespaces:
        entry = {"identity": ref(get(source, "namespace/" + name)), "pvcs": [], "workloads": [], "pods": []}
        for claim in get(source, "pvc", name)["items"]:
            spec = claim["spec"]
            volume = get(source, "pv/" + spec["volumeName"])
            entry["pvcs"].append({**ref(claim), "volume": ref(volume),
                                  "storageClass": spec.get("storageClassName"),
                                  "accessModes": spec.get("accessModes", []),
                                  "capacity": spec.get("resources", {}).get("requests", {}).get("storage"),
                                  "reclaimPolicy": volume["spec"].get("persistentVolumeReclaimPolicy")})
        for kind in ("deployments", "statefulsets", "cronjobs"):
            for obj in get(source, kind, name)["items"]:
                entry["workloads"].append({**ref(obj), "kind": obj["kind"],
                                          "replicas": obj["spec"].get("replicas"),
                                          "suspend": obj["spec"].get("suspend")})
        for pod in get(source, "pods", name)["items"]:
            entry["pods"].append({**ref(pod), "containers": [
                {"name": c["name"], "image": c["image"], "mounts": c.get("volumeMounts", [])}
                for c in pod["spec"]["containers"]], "claims": [
                {"volume": v["name"], "claim": v["persistentVolumeClaim"]["claimName"]}
                for v in pod["spec"].get("volumes", []) if "persistentVolumeClaim" in v]})
        plan["namespaces"].append(entry)
    # Flux references only: no URLs, credentials, manifests or inventory payload.
    for obj in get(source, "kustomizations.kustomize.toolkit.fluxcd.io", "flux-system")["items"]:
        plan["flux"].append({**ref(obj), "suspend": bool(obj["spec"].get("suspend", False)),
                             "targetNamespace": obj["spec"].get("targetNamespace"),
                             "path": obj["spec"].get("path")})
    return plan


def authorize(plan, expected_hash, namespace, claim, coordinated):
    if not coordinated or digest(plan) != expected_hash:
        raise ValueError("Require parent-coordinated operation and reviewed exact plan hash")
    entries = [e for e in plan["namespaces"] if e["identity"]["name"] == namespace]
    if len(entries) != 1 or not any(p["name"] == claim for p in entries[0]["pvcs"]):
        raise ValueError("Namespace/PVC outside reviewed scope")
    if plan["source"] == plan["target"] or plan["sourceUID"] == plan["targetUID"]:
        raise ValueError("Source/target alias forbidden")
    for key in ("source", "target"):
        if get(plan[key], "namespace/kube-system")["metadata"]["uid"] != plan[key + "UID"]:
            raise ValueError("Cluster identity drift")
    if get(plan["source"], "namespace/" + namespace)["metadata"]["uid"] != entries[0]["identity"]["uid"]:
        raise ValueError("Namespace identity drift")
    expected = next(p for p in entries[0]["pvcs"] if p["name"] == claim)
    current = get(plan["source"], "pvc/" + claim, namespace)
    if current["metadata"]["uid"] != expected["uid"] or current["spec"].get("volumeName") != expected["volume"]["name"]:
        raise ValueError("Source PVC binding drift")


def verify_helper(context, namespace, pod_name, container, claim, mount, readonly):
    pod = get(context, "pod/" + pod_name, namespace)
    volumes = {v["name"]: v.get("persistentVolumeClaim", {}).get("claimName") for v in pod["spec"].get("volumes", [])}
    containers = [c for c in pod["spec"]["containers"] if c["name"] == container]
    if len(containers) != 1 or not mount.startswith("/") or mount == "/" or ".." in mount.split("/"):
        raise ValueError("Explicit container and non-root mounted data directory required")
    mounts = [m for m in containers[0].get("volumeMounts", []) if m["mountPath"] == mount and volumes.get(m["name"]) == claim]
    if len(mounts) != 1 or mounts[0].get("subPath") or bool(mounts[0].get("readOnly", False)) != readonly:
        raise ValueError("Require exact whole PVC mount, read-only for backup")


def frozen(plan, namespace):
    # Parent performs suspension/freeze. Shared Flux roots require separate review.
    for owner in plan["flux"]:
        current = get(plan["source"], "kustomization/" + owner["name"], owner["namespace"])
        if current["metadata"]["uid"] != owner["uid"] or not current["spec"].get("suspend", False):
            raise ValueError("Source Flux owners must be suspended by parent first")
    for obj in get(plan["source"], "deployments", namespace)["items"]:
        if obj["spec"].get("replicas", 1) != 0 or obj.get("status", {}).get("replicas", 0) != 0:
            raise ValueError("Source application writer deployment must be stopped")
    for obj in get(plan["source"], "cronjobs", namespace)["items"]:
        if not obj["spec"].get("suspend", False):
            raise ValueError("Source CronJobs must be suspended")
    for obj in get(plan["source"], "jobs", namespace)["items"]:
        if obj.get("status", {}).get("active", 0):
            raise ValueError("Source job still active")


def quiesced_claim(context, namespace, claim, helper):
    for pod in get(context, "pods", namespace)["items"]:
        if pod["metadata"]["name"] == helper or pod.get("status", {}).get("phase") in ("Succeeded", "Failed"):
            continue
        if any(v.get("persistentVolumeClaim", {}).get("claimName") == claim for v in pod["spec"].get("volumes", [])):
            raise ValueError("PVC is still mounted by a workload; stop database/writers before raw copy")


def mysql_command(prefix, operation):
    credential = 'test -n "$MYSQL_ROOT_PASSWORD" && test -n "$MYSQL_DATABASE" && '
    queries = {
        "frozen": 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -e "SELECT @@global.super_read_only"',
        "dump": 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --single-transaction --skip-comments --order-by-primary --skip-extended-insert --routines --events --triggers --databases "$MYSQL_DATABASE"',
        "empty": 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot --database="$MYSQL_DATABASE" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE()"',
        "restore": 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot',
    }
    return prefix + ["sh", "-c", credential + queries[operation]]


def render_helper(plan, namespace, claim, side, image, storage_class=None, uid=0, gid=0):
    entry = next(e for e in plan["namespaces"] if e["identity"]["name"] == namespace)
    pvc = next(p for p in entry["pvcs"] if p["name"] == claim)
    if side not in ("source", "target") or not re.fullmatch(r"[^\s]+@sha256:[a-f0-9]{64}", image):
        raise ValueError("Reviewed helper image digest and side required")
    if not isinstance(uid, int) or not isinstance(gid, int) or uid < 0 or gid < 0:
        raise ValueError("Reviewed numeric helper UID/GID required")
    ident = digest({"plan": digest(plan), "namespace": namespace, "claim": claim, "side": side})[:12]
    pod = {"apiVersion": "v1", "kind": "Pod", "metadata": {"name": "migration-" + ident,
           "namespace": namespace, "labels": {"envplane.io/migration-plan": digest(plan)[:32]}},
           "spec": {"automountServiceAccountToken": False, "restartPolicy": "Never",
                    "securityContext": {"runAsUser": uid, "runAsGroup": gid, "runAsNonRoot": uid != 0,
                                        "seccompProfile": {"type": "RuntimeDefault"}},
                    "containers": [{"name": "data", "image": image, "command": ["sleep", "3600"],
                                    "securityContext": {"allowPrivilegeEscalation": False,
                                                        "capabilities": {"drop": ["ALL"]}},
                                    "resources": {"requests": {"cpu": "10m", "memory": "32Mi"},
                                                  "limits": {"cpu": "250m", "memory": "128Mi"}},
                                    "volumeMounts": [{"name": "data", "mountPath": "/migration-data", "readOnly": side == "source"}]}],
                    "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": claim}}]}}
    result = {"context": plan[side], "pod": pod}
    if uid == 0:
        # Cold filesystem preservation needs ownership/mode operations. This is
        # only for namespaces that permit root helpers; never Restricted auth.
        pod["spec"]["containers"][0]["securityContext"]["capabilities"]["add"] = ["CHOWN", "DAC_OVERRIDE", "FOWNER"]
    if side == "target":
        if not storage_class or not re.fullmatch(r"[a-z0-9][a-z0-9.-]{0,251}[a-z0-9]", storage_class):
            raise ValueError("Explicit reviewed target StorageClass mapping required")
        # New binding only: never reuse volumeName, UID, claimRef, hostPath or old PVs.
        result["pvc"] = {"apiVersion": "v1", "kind": "PersistentVolumeClaim",
            "metadata": {"name": claim, "namespace": namespace},
            "spec": {"accessModes": pvc["accessModes"], "storageClassName": storage_class,
                     "resources": {"requests": {"storage": pvc["capacity"]}}}}
    return result


def stream(first, second, output=None):
    # Never buffer decrypted data or expose stdout/stderr from data commands.
    a = subprocess.Popen(first, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        b = subprocess.Popen(second, stdin=a.stdout, stdout=output or subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        a.stdout.close()
        if b.wait() or a.wait():
            raise ValueError("Encrypted data stream failed; artifact is not usable")
    finally:
        if a.poll() is None:
            a.terminate()
            a.wait()


def tree_manifest(context, namespace, pod, container, mount):
    # Reviewed data helper must include Python 3; no filenames/content printed.
    program = '''import hashlib,json,os,stat,sys
root=sys.argv[1]; records=[]
for base,dirs,files in os.walk(root, followlinks=False):
 for name in sorted(dirs+files):
  path=os.path.join(base,name); s=os.lstat(path); mode=s.st_mode
  row=[os.path.relpath(path,root),stat.S_IMODE(mode),s.st_uid,s.st_gid,int(s.st_mtime)]
  if stat.S_ISLNK(mode): row += ["link",os.readlink(path)]
  elif stat.S_ISDIR(mode): row += ["directory"]
  elif stat.S_ISREG(mode):
   h=hashlib.sha256()
   with open(path,"rb") as f:
    for block in iter(lambda:f.read(1048576),b""): h.update(block)
   row += ["file",s.st_size,h.hexdigest()]
  else: raise ValueError("unsupported special file")
  records.append(row)
print(hashlib.sha256(json.dumps(sorted(records),separators=(",",":"),ensure_ascii=True).encode()).hexdigest())
'''
    args = ["kubectl", "--context", context, "-n", namespace, "exec", pod, "-c", container,
            "--", "python3", "-c", program, mount]
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        raise ValueError("Checksum rehearsal command failed")
    checksum = result.stdout.decode().strip()
    if not re.fullmatch(r"[a-f0-9]{64}", checksum):
        raise ValueError("Invalid checksum response")
    return checksum


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("inventory", "render-helper", "backup-pvc", "restore-pvc", "checksum-pvc", "backup-mysql", "restore-mysql", "checksum-mysql"))
    parser.add_argument("--source")
    parser.add_argument("--target")
    parser.add_argument("--namespace", action="append", required=True)
    parser.add_argument("--out")
    parser.add_argument("--plan")
    parser.add_argument("--reviewed-sha256")
    parser.add_argument("--parent-coordinated", action="store_true")
    parser.add_argument("--claim")
    parser.add_argument("--pod")
    parser.add_argument("--container")
    parser.add_argument("--mount")
    parser.add_argument("--recipient")
    parser.add_argument("--identity-file")
    parser.add_argument("--archive")
    parser.add_argument("--archive-sha256")
    parser.add_argument("--side", choices=("source", "target"), default="source")
    parser.add_argument("--helper-image")
    parser.add_argument("--target-storage-class")
    parser.add_argument("--helper-uid", type=int, default=0)
    parser.add_argument("--helper-gid", type=int, default=0)
    args = parser.parse_args()
    if args.mode == "inventory":
        plan = inventory(args.source, args.target, args.namespace)
        write_private(args.out, plan)
        print("Reviewed plan SHA256:", digest(plan))
        return
    if len(args.namespace) != 1:
        raise ValueError("Transfer exactly one namespace/PVC per operation")
    ns = args.namespace[0]
    plan = json.loads(Path(args.plan).read_text())
    if args.mode == "render-helper":
        rendered = render_helper(plan, ns, args.claim, args.side, args.helper_image, args.target_storage_class,
                                 args.helper_uid, args.helper_gid)
        items = []
        if args.side == "target":
            items += [{"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": ns,
                       "labels": {"envplane.io/migration-plan": digest(plan)[:32]}}}, rendered["pvc"]]
        items.append(rendered["pod"])
        write_private(args.out, {"apiVersion": "v1", "kind": "List", "items": items})
        return
    authorize(plan, args.reviewed_sha256, ns, args.claim, args.parent_coordinated)
    restore = args.mode in ("restore-pvc", "restore-mysql")
    mysql = args.mode in ("backup-mysql", "restore-mysql", "checksum-mysql")
    context = plan["target"] if restore or (args.mode.startswith("checksum-") and args.side == "target") else plan["source"]
    verify_helper(context, ns, args.pod, args.container, args.claim, args.mount, not (restore or mysql))
    frozen(plan, ns)
    prefix = ["kubectl", "--context", context, "-n", ns, "exec", "-i", args.pod, "-c", args.container, "--"]
    if mysql:
        pod = get(context, "pod/" + args.pod, ns)
        image = next(c["image"] for c in pod["spec"]["containers"] if c["name"] == args.container)
        if not re.fullmatch(r"mysql:8\.4(?:\.\d+)?(?:@sha256:[a-f0-9]{64})?", image):
            raise ValueError("This reviewed workflow supports only the observed MySQL 8.4 image")
    if args.mode in ("backup-pvc", "checksum-pvc"):
        quiesced_claim(context, ns, args.claim, args.pod)
    if args.mode in ("backup-pvc", "backup-mysql"):
        if not args.recipient or not args.recipient.startswith("age1"):
            raise ValueError("Explicit age public recipient required")
        if mysql:
            check = subprocess.run(mysql_command(prefix, "frozen"), capture_output=True)
            if check.returncode or check.stdout.strip() != b"1":
                raise ValueError("Parent must enable MySQL super_read_only before logical dump")
        fd = os.open(args.archive, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as handle:
            source = mysql_command(prefix, "dump") if mysql else prefix + ["tar", "-C", args.mount, "-cpf", "-", "."]
            stream(source, ["age", "-r", args.recipient], handle)
        print("Encrypted archive SHA256:", file_digest(args.archive))
    elif restore:
        if file_digest(args.archive) != args.archive_sha256:
            raise ValueError("Encrypted archive differs from parent's recorded checksum")
        identity = Path(args.identity_file)
        if identity.is_symlink() or identity.stat().st_mode & 0o077:
            raise ValueError("Private non-symlink decryption identity required")
        if mysql:
            empty = subprocess.run(mysql_command(prefix, "empty"), capture_output=True)
            if empty.returncode or empty.stdout.strip() != b"0":
                raise ValueError("Refuse overwrite: target database must have no application tables")
        else:
            quiesced_claim(context, ns, args.claim, args.pod)
            empty = subprocess.run(prefix + ["sh", "-c", 'test -z "$(ls -A "$1")"', "sh", args.mount], capture_output=True)
            if empty.returncode:
                raise ValueError("Refuse overwrite: target PVC directory is not empty")
        # Parent supplies an isolated fresh MySQL instance for logical rehearsal;
        # no automatic schema deletion, credential import or account recreation.
        destination = mysql_command(prefix, "restore") if mysql else prefix + ["tar", "-C", args.mount, "-xpf", "-"]
        stream(["age", "-d", "-i", str(identity), args.archive], destination)
    else:
        if mysql:
            value = hashlib.sha256()
            with subprocess.Popen(mysql_command(prefix, "dump"), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
                for block in iter(lambda: process.stdout.read(1024 * 1024), b""):
                    value.update(block)
                if process.wait():
                    raise ValueError("Logical checksum failed")
            print("Logical database SHA256:", value.hexdigest())
        else:
            print("Data tree SHA256:", tree_manifest(context, ns, args.pod, args.container, args.mount))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError):
        print("Scoped migration refused; no data/credentials printed", file=sys.stderr)
        sys.exit(1)
