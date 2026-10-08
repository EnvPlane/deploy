#!/usr/bin/env python3
"""Administrator cold-copy of reviewed PVC paths, without privileged Pods.

Requires stopped writers, exact plan hashes, both cluster identities and a
private age identity. Never deletes PVCs/PVs, changes source permissions, uses
PTY SSH, or prints file names/content. Original source data stays untouched.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

spec = importlib.util.spec_from_file_location("migration", Path(__file__).with_name("scoped-data-migration.py"))
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)

TREE = '''import hashlib,json,os,stat,sys
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


def node(context, args, capture=True):
    result = subprocess.run(["docker", "exec", "-i", context] + args, capture_output=capture)
    if result.returncode:
        raise ValueError("Scoped node operation failed")
    return result.stdout


def volume_path(plan, namespace, claim, side):
    context = plan[side]
    pvc = migration.get(context, "pvc/" + claim, namespace)
    pv = migration.get(context, "pv/" + pvc["spec"]["volumeName"])
    ref = pv["spec"]["claimRef"]
    if ref["namespace"] != namespace or ref["name"] != claim or ref["uid"] != pvc["metadata"]["uid"] or pvc["status"]["phase"] != "Bound":
        raise ValueError("PVC/PV binding drift")
    path = pv["spec"].get("hostPath", {}).get("path") or pv["spec"].get("local", {}).get("path")
    expected = "/tmp/hostpath-provisioner/" + namespace + "/" + claim
    expected_local = "/opt/envplane-local-path/" + pv["metadata"]["name"] + "_" + namespace + "_" + claim
    if path not in (expected, expected_local):
        raise ValueError("PV path outside exact reviewed provisioner layout")
    check = 'import os,sys; p=sys.argv[1]; assert os.path.isdir(p) and os.path.realpath(p)==p'
    node(context, ["python3", "-c", check, path])
    return path


def checksum(context, path):
    result = node(context, ["python3", "-c", TREE, path]).decode().strip()
    if len(result) != 64 or any(c not in "0123456789abcdef" for c in result):
        raise ValueError("Invalid data tree checksum")
    return result


def run(args):
    if args.target != args.approve_target or os.path.islink(args.identity) or os.stat(args.identity).st_mode & 0o077:
        raise ValueError("Exact target approval and private identity required")
    directory = Path(args.directory)
    if directory.is_symlink() or directory.stat().st_mode & 0o077:
        raise ValueError("Private non-symlink backup directory required")
    entries = []
    for path, reviewed in zip(args.plan, args.reviewed_sha256, strict=True):
        plan = json.loads(Path(path).read_text())
        if plan["target"] != args.target or migration.digest(plan) != reviewed:
            raise ValueError("Reviewed plan mismatch")
        for side in ("source", "target"):
            if node(plan[side], ["hostname"]).decode().strip() != plan[side]:
                raise ValueError("Docker node identity mismatch")
        for ns in plan["namespaces"]:
            namespace = ns["identity"]["name"]
            if not ns["pvcs"]:
                continue
            migration.frozen(plan, namespace)
            for workload in migration.get(plan["source"], "statefulsets", namespace)["items"]:
                if workload["spec"].get("replicas", 1) or workload.get("status", {}).get("replicas", 0):
                    raise ValueError("Source database must be shut down")
            for claim in ns["pvcs"]:
                name = claim["name"]
                migration.authorize(plan, reviewed, namespace, name, True)
                for side in ("source", "target"):
                    migration.quiesced_claim(plan[side], namespace, name, "")
                source_path = volume_path(plan, namespace, name, "source")
                target_path = volume_path(plan, namespace, name, "target")
                node(plan["target"], ["python3", "-c", "import os,sys; assert not any(os.scandir(sys.argv[1]))", target_path])
                archive = directory / (namespace + "--" + name + ".age")
                if archive.exists():
                    raise ValueError("Refuse overwrite of backup archive")
                entries.append((plan, namespace, name, source_path, target_path, archive))
    # All binding/freeze/empty checks complete before the first data write.
    ledger = []
    for plan, namespace, name, source_path, target_path, archive in entries:
        before = checksum(plan["source"], source_path)
        with os.fdopen(os.open(archive, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), "wb") as handle:
            migration.stream(["docker", "exec", "-i", plan["source"], "tar", "--numeric-owner", "-C", source_path, "-cpf", "-", "."], ["age", "-r", args.recipient], handle)
        archive_hash = migration.file_digest(archive)
        migration.stream(["age", "-d", "-i", args.identity, str(archive)], ["docker", "exec", "-i", plan["target"], "tar", "--numeric-owner", "-C", target_path, "-xpf", "-"])
        after = checksum(plan["target"], target_path)
        if before != after or checksum(plan["source"], source_path) != before:
            raise ValueError("Cold restore integrity or source stability failed")
        ledger.append({"namespace": namespace, "claim": name, "archiveSHA256": archive_hash, "dataTreeSHA256": before, "restored": True})
        print(json.dumps({"namespace": namespace, "claim": name, "integrityVerified": True}), flush=True)
    migration.write_private(directory / "data-integrity-ledger.json", {"schemaVersion": 1, "target": args.target, "sourcePreserved": True, "claims": ledger})
    print(json.dumps({"coldRestoreVerified": True, "claimCount": len(ledger), "sourcePreserved": True}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", action="append", required=True)
    parser.add_argument("--reviewed-sha256", action="append", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--approve-target", required=True)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--recipient", required=True)
    parser.add_argument("--directory", required=True)
    try:
        run(parser.parse_args())
    except (ValueError, KeyError, TypeError, OSError):
        print("Scoped cold restore rejected; source retained and no data/credentials printed", file=sys.stderr)
        sys.exit(1)
