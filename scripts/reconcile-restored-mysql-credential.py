#!/usr/bin/env python3
"""Explicit candidate-only account reconciliation after verified cold restore.

Uses an ephemeral startup init-file, never skip-grant-tables, root-password
extraction, dataset ownership changes, database deletion or plaintext host files.
Only the configured existing application user is changed to its current Secret.
"""
import argparse
import base64
import json
from pathlib import Path
import re
import subprocess
import sys


def call(context, namespace, args, data=None):
    result = subprocess.run(["kubectl", "--context", context, "-n", namespace] + args, input=data, capture_output=True)
    if result.returncode:
        raise ValueError("Scoped MySQL reconciliation operation rejected")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--authorize-namespace", required=True)
    parser.add_argument("--integrity-ledger", required=True)
    parser.add_argument("mode", choices=("prepare", "cleanup"))
    args = parser.parse_args()
    ledger = json.loads(Path(args.integrity_ledger).read_text())
    if args.namespace != args.authorize_namespace or ledger["target"] != args.context or ledger.get("source") == args.context or not any(c["namespace"] == args.namespace and c["claim"] == "mysql-data" and c["restored"] is True for c in ledger["claims"]):
        raise ValueError("Exact verified candidate restore approval required")
    obj = json.loads(call(args.context, args.namespace, ["get", "statefulset", "mysql", "-o", "json"]))
    spec = obj["spec"]["template"]["spec"]
    containers = [c for c in spec["containers"] if c["name"] == "mysql"]
    if len(containers) != 1:
        raise ValueError("Expected exact MySQL container")
    container = containers[0]
    volume_name = "migration-db-credential-init"
    secret_name = "envplane-migration-mysql-reconcile"
    init_args = ["--init-file=/var/run/envplane-migration/mysql-init.sql"]
    if args.mode == "prepare":
        if container.get("args"):
            raise ValueError("Existing MySQL args need operator review")
        username = next(e["value"] for e in container["env"] if e["name"] == "MYSQL_USER")
        reference = next(e["valueFrom"]["secretKeyRef"] for e in container["env"] if e["name"] == "MYSQL_PASSWORD")
        if not re.fullmatch(r"[a-zA-Z0-9_]{1,32}", username):
            raise ValueError("Reviewed application username required")
        secret = json.loads(call(args.context, args.namespace, ["get", "secret", reference["name"], "-o", "json"]))
        password = base64.b64decode(secret["data"][reference["key"]], validate=True).decode()
        if not re.fullmatch(r"[A-Za-z0-9_./+=:@!#$%^&*()-]{8,128}", password):
            raise ValueError("Unsupported credential character set requires operator review")
        sql = f"ALTER USER '{username}'@'%' IDENTIFIED BY '{password}';\n"
        if any(v["name"] == volume_name for v in spec.get("volumes", [])) or any(m["name"] == volume_name for m in container.get("volumeMounts", [])):
            raise ValueError("Existing reserved init-file mount requires review")
        payload = {"apiVersion": "v1", "kind": "Secret", "metadata": {"name": secret_name, "namespace": args.namespace, "labels": {"envplane.io/purpose": "candidate-credential-reconciliation", "envplane.io/mysql-statefulset-uid": obj["metadata"]["uid"]}}, "type": "Opaque", "data": {"mysql-init.sql": base64.b64encode(sql.encode()).decode()}}
        call(args.context, args.namespace, ["create", "-f", "-"], json.dumps(payload).encode())
        spec.setdefault("volumes", []).append({"name": volume_name, "secret": {"secretName": secret_name}})
        container.setdefault("volumeMounts", []).append({"name": volume_name, "mountPath": "/var/run/envplane-migration", "readOnly": True})
        container["args"] = init_args
    else:
        if container.get("args") != init_args:
            raise ValueError("Only owned init-file configuration can be removed")
        owned = json.loads(call(args.context, args.namespace, ["get", "secret", secret_name, "-o", "json"]))
        labels = owned["metadata"].get("labels", {})
        if labels.get("envplane.io/purpose") != "candidate-credential-reconciliation" or labels.get("envplane.io/mysql-statefulset-uid") != obj["metadata"]["uid"]:
            raise ValueError("Temporary Secret ownership requires review")
        mounts = [m for m in container.get("volumeMounts", []) if m["name"] == volume_name]
        volumes = [v for v in spec.get("volumes", []) if v["name"] == volume_name]
        if len(mounts) != 1 or mounts[0].get("mountPath") != "/var/run/envplane-migration" or mounts[0].get("readOnly") is not True or len(volumes) != 1 or volumes[0].get("secret", {}).get("secretName") != secret_name:
            raise ValueError("Only exact owned init-file mounts can be removed")
        container["args"] = None
        container["volumeMounts"] = [m for m in container["volumeMounts"] if m["name"] != volume_name]
        spec["volumes"] = [v for v in spec["volumes"] if v["name"] != volume_name]
    update = [{"op": "test", "path": "/metadata/uid", "value": obj["metadata"]["uid"]},
              {"op": "test", "path": "/metadata/resourceVersion", "value": obj["metadata"]["resourceVersion"]},
              {"op": "replace", "path": "/spec/template/spec", "value": spec}]
    call(args.context, args.namespace, ["patch", "statefulset", "mysql", "--type=json", "--patch-file=/dev/stdin"], json.dumps(update).encode())
    if args.mode == "cleanup":
        call(args.context, args.namespace, ["rollout", "status", "statefulset/mysql", "--timeout=120s"])
        deletion = {"apiVersion": "v1", "kind": "DeleteOptions", "preconditions": {"uid": owned["metadata"]["uid"], "resourceVersion": owned["metadata"]["resourceVersion"]}}
        call(args.context, args.namespace, ["delete", "--raw", f"/api/v1/namespaces/{args.namespace}/secrets/{secret_name}", "-f", "-"], json.dumps(deletion).encode())
    print(json.dumps({"namespace": args.namespace, "candidateOnly": True, "mode": args.mode, "databaseDataPreserved": True, "authBypass": False}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, StopIteration, OSError):
        print("Candidate MySQL credential operation rejected; no credentials printed", file=sys.stderr)
        sys.exit(1)
