#!/usr/bin/env python3
"""Seal the reviewed candidate's replacement SA kubeconfig without logging it."""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from urllib.parse import urlparse


def run(args):
    result = subprocess.run(args, capture_output=True)
    if result.returncode:
        raise ValueError("Candidate credential read failed")
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", required=True)
    parser.add_argument("--cluster-id", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--secret", required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--server-name", required=True)
    parser.add_argument("--recipient", required=True)
    parser.add_argument("--archive", required=True)
    args = parser.parse_args()
    url = urlparse(args.server)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment or not args.recipient.startswith("age1"):
        raise ValueError("Reviewed HTTPS endpoint and encryption required")
    secret = run(["kubectl", "--context", args.target, "-n", args.namespace, "get", "secret", args.secret, "-o", "json"])
    expected_sa = "envplane-remote-cluster-" + args.cluster_id
    if secret.get("type") != "kubernetes.io/service-account-token" or secret["metadata"].get("annotations", {}).get("kubernetes.io/service-account.name") != expected_sa:
        raise ValueError("Candidate ServiceAccount binding rejected")
    import base64
    token = base64.b64decode(secret["data"]["token"], validate=True).decode()
    ca = secret["data"]["ca.crt"]
    if not token or not ca:
        raise ValueError("Candidate token or CA unavailable")
    payload = {"apiVersion": "v1", "kind": "Config", "current-context": args.cluster_id,
               "clusters": [{"name": args.cluster_id, "cluster": {"server": args.server, "tls-server-name": args.server_name, "certificate-authority-data": ca}}],
               "contexts": [{"name": args.cluster_id, "context": {"cluster": args.cluster_id, "user": expected_sa}}],
               "users": [{"name": expected_sa, "user": {"token": token}}]}
    raw = json.dumps(payload).encode()
    with os.fdopen(os.open(args.archive, os.O_EXCL | os.O_WRONLY | os.O_CREAT, 0o600), "wb") as handle:
        result = subprocess.run(["age", "-r", args.recipient], input=raw, stdout=handle, stderr=subprocess.DEVNULL)
        if result.returncode:
            raise ValueError("Candidate credential encryption failed")
    print(json.dumps({"encrypted": True, "logicalClusterID": args.cluster_id, "credentialSHA256": hashlib.sha256(raw).hexdigest()}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError):
        print("Candidate credential operation rejected; no credential output", file=sys.stderr)
        sys.exit(1)
