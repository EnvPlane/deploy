#!/usr/bin/env python3
"""Reviewed administrator-only preparation of a single existing MySQL source.

Preview reads metadata only. Apply requires the exact reviewed plan digest and
restart acknowledgement. Never invoke this as an ordinary copy worker. Supported
layout: one-replica official MySQL 8 StatefulSet, explicit source PVC, default
entrypoint/config include path, root password already referenced from a Secret.
"""
import argparse
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile


class Refused(Exception):
    """Safe, fixed error messages only; never include subprocess output."""


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def valid_name(value):
    return isinstance(value, str) and len(value) <= 63 and re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", value)


def run(argv, data=None, timeout=45):
    try:
        result = subprocess.run(argv, input=data, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Refused("Preparation operation unavailable or timed out; no diagnostics exposed") from exc
    if result.returncode:
        raise Refused("Preparation operation denied or failed; inspect protected operator diagnostics")
    return result.stdout


class Kubernetes:
    def __init__(self, kubeconfig, context, namespace):
        self.prefix = ["kubectl", "--kubeconfig", kubeconfig, "--context", context]
        self.namespace = namespace

    def call(self, args, data=None, timeout=45):
        return run(self.prefix + ["-n", self.namespace] + args, data, timeout)

    def get(self, kind, name):
        return json.loads(self.call(["get", kind, name, "-o", "json"]))

    def optional_secret(self, name):
        raw = self.call(["get", "secret", name, "--ignore-not-found", "-o", "json"])
        return json.loads(raw) if raw.strip() else None

    def create(self, obj):
        return json.loads(self.call(["create", "-f", "-", "-o", "json"], json.dumps(obj).encode()))


def metadata(obj):
    meta = obj.get("metadata", {})
    if not meta.get("uid") or meta.get("deletionTimestamp"):
        raise Refused("Live source identity unavailable")
    return meta


def plan_for(cluster, sts, pvc, service, tenant, project):
    """No Secret data or raw workload template is returned in the review."""
    ns = metadata(sts).get("namespace")
    for value in (ns, metadata(sts).get("name"), metadata(pvc).get("name"), metadata(service).get("name")):
        if not valid_name(value):
            raise Refused("Unsupported Kubernetes identity")
    if not tenant or not project or len(tenant) > 128 or len(project) > 128:
        raise Refused("Explicit tenant and project scope required")
    if sts.get("kind") != "StatefulSet" or sts["spec"].get("replicas", 1) != 1:
        raise Refused("Only one-replica StatefulSet sources are supported")
    if sts["spec"].get("updateStrategy", {}).get("type", "RollingUpdate") != "RollingUpdate":
        raise Refused("Unsupported source rollout strategy")
    if sts["spec"].get("updateStrategy", {}).get("rollingUpdate", {}).get("partition", 0) != 0:
        raise Refused("Partitioned source rollout requires independent review")
    template = sts["spec"]["template"]
    pod = template["spec"]
    containers = pod.get("containers", [])
    if len(containers) != 1 or pod.get("initContainers"):
        raise Refused("Sidecars or init containers require independent review")
    c = containers[0]
    image = c.get("image", "")
    if not re.fullmatch(r"(?:(?:docker\.io/)?library/|docker\.io/)?mysql(?::8\.(?:0|4)(?:\.[0-9]+)?(?:-[a-z0-9.-]+)?)?(?:@sha256:[a-f0-9]{64})?", image) or (":8." not in image and "@sha256:" not in image):
        raise Refused("Reviewed official MySQL 8 image required; latest is unsupported")
    if c.get("command") or c.get("args") or c.get("envFrom"):
        raise Refused("Custom entrypoint, args or envFrom require independent review")
    env = {}
    for entry in c.get("env", []):
        if entry.get("name") in env:
            raise Refused("Ambiguous source environment")
        env[entry.get("name")] = entry
    database = env.get("MYSQL_DATABASE", {}).get("value", "")
    user = env.get("MYSQL_USER", {}).get("value", "")
    if not re.fullmatch(r"[A-Za-z0-9_]{1,64}", database) or database.lower() in ("mysql", "sys", "information_schema", "performance_schema"):
        raise Refused("Explicit application database required")
    if not re.fullmatch(r"[A-Za-z0-9_]{1,32}", user) or user.lower() == "root":
        raise Refused("Existing non-root application user required")
    root = env.get("MYSQL_ROOT_PASSWORD", {}).get("valueFrom", {}).get("secretKeyRef", {})
    app = env.get("MYSQL_PASSWORD", {}).get("valueFrom", {}).get("secretKeyRef", {})
    for ref in (root, app):
        if not valid_name(ref.get("name")) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", ref.get("key", "")) or ref.get("optional"):
            raise Refused("Existing required root/app Secret references required")
    volumes = {v["name"]: v for v in pod.get("volumes", [])}
    source_mount = [m for m in c.get("volumeMounts", []) if m.get("mountPath") == "/var/lib/mysql"]
    if len(source_mount) != 1 or volumes.get(source_mount[0]["name"], {}).get("persistentVolumeClaim", {}).get("claimName") != pvc["metadata"]["name"]:
        raise Refused("Exact explicit source PVC mount required")
    if pvc.get("status", {}).get("phase") != "Bound" or pvc["metadata"].get("namespace") != ns or not pvc.get("spec", {}).get("volumeName"):
        raise Refused("Bound source PVC in the workload namespace required")
    if service["metadata"].get("namespace") != ns or service.get("spec", {}).get("type") == "ExternalName":
        raise Refused("Same-namespace selected Service required")
    selector = service.get("spec", {}).get("selector", {})
    labels = template.get("metadata", {}).get("labels", {})
    if not selector or any(labels.get(k) != v for k, v in selector.items()):
        raise Refused("Service does not select the reviewed source")
    ports = [p for p in service["spec"].get("ports", []) if p.get("port") == 3306 and p.get("targetPort", 3306) in (3306, "mysql") and p.get("protocol", "TCP") == "TCP"]
    if len(ports) != 1:
        raise Refused("Unambiguous MySQL Service port required")
    original = digest(template)
    base = {"version": 1, "clusterUID": metadata(cluster)["uid"], "tenant": tenant, "project": project, "namespace": ns,
            "statefulSet": sts["metadata"]["name"], "statefulSetUID": sts["metadata"]["uid"], "sourceTemplateDigest": original,
            "pvc": pvc["metadata"]["name"], "pvcUID": pvc["metadata"]["uid"], "pv": pvc["spec"]["volumeName"],
            "service": service["metadata"]["name"], "serviceUID": service["metadata"]["uid"], "serviceSpecDigest": digest(service["spec"]), "container": c["name"], "image": image,
            "database": database, "rootSecret": root["name"], "rootPasswordKey": root["key"], "appSecret": app["name"], "appPasswordKey": app["key"],
            "tlsServerName": service["metadata"]["name"] + "." + ns + ".svc",
            "grants": ["SELECT, SHOW VIEW, TRIGGER, EVENT ON application schema", "SHOW_ROUTINE, BACKUP_ADMIN ON *.*"],
            "sourceRestartRequired": True}
    ident = digest(base)[:20]
    base.update({"backupUsername": "ep_backup_" + ident, "credentialSecret": "ep-mysql-backup-" + ident,
                 "tlsSecret": "ep-mysql-tls-" + ident, "caSecret": "ep-mysql-ca-" + ident,
                 "desiredStateOwner": sts["metadata"].get("annotations", {}).get("meta.helm.sh/release-name", "")})
    for m in c.get("volumeMounts", []):
        path = m.get("mountPath", "")
        if path in ("/etc", "/etc/mysql", "/etc/mysql/conf.d") or path.startswith("/etc/envplane") or path.startswith("/etc/mysql/conf.d/"):
            raise Refused("Existing config mounts require independent ownership review")
    base["digest"] = digest(base)
    return base


def sql_create(plan, password):
    if not re.fullmatch(r"[a-f0-9]{64}", password):
        raise Refused("Invalid generated credential")
    username, database = plan["backupUsername"], plan["database"]
    if not re.fullmatch(r"ep_backup_[a-f0-9]{20}", username) or not re.fullmatch(r"[A-Za-z0-9_]{1,64}", database):
        raise Refused("Unsafe SQL identity")
    return (f"CREATE USER '{username}'@'%' IDENTIFIED BY '{password}' REQUIRE SSL;\n"
            f"GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON `{database}`.* TO '{username}'@'%';\n"
            f"GRANT SHOW_ROUTINE, BACKUP_ADMIN ON *.* TO '{username}'@'%';\n")


def tls_material(plan):
    """Only temporary owner-readable files; CA signer is not retained/exported."""
    with tempfile.TemporaryDirectory(prefix="envplane-mysql-tls-") as directory:
        os.chmod(directory, 0o700)
        base = Path(directory)
        ca_key, ca, key, csr, cert, extensions = [base / name for name in ("ca.key", "ca.pem", "server.key", "server.csr", "server.pem", "extensions")]
        extensions.write_text("basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:" + plan["tlsServerName"] + "\n")
        previous = os.umask(0o077)
        try:
            run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-keyout", str(ca_key), "-out", str(ca), "-days", "365", "-subj", "/CN=envplane-source-ca", "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign"])
            run(["openssl", "req", "-new", "-newkey", "rsa:3072", "-nodes", "-keyout", str(key), "-out", str(csr), "-subj", "/CN=" + plan["tlsServerName"]])
            run(["openssl", "x509", "-req", "-in", str(csr), "-CA", str(ca), "-CAkey", str(ca_key), "-CAcreateserial", "-out", str(cert), "-days", "90", "-extfile", str(extensions)])
            run(["openssl", "verify", "-CAfile", str(ca), "-verify_hostname", plan["tlsServerName"], str(cert)])
            return {"ca.pem": ca.read_bytes(), "server.pem": cert.read_bytes(), "server.key": key.read_bytes()}
        finally:
            os.umask(previous)


def owned_secret(plan, name, data, annotations=None):
    return {"apiVersion": "v1", "kind": "Secret", "metadata": {"name": name, "namespace": plan["namespace"],
            "labels": {"envplane.io/purpose": "mysql-source-preparation"},
            "annotations": {"envplane.io/preparation-digest": plan["digest"], "envplane.io/source-uid": plan["statefulSetUID"], **(annotations or {})}},
            "immutable": True, "type": "Opaque", "data": {k: base64.b64encode(v).decode() for k, v in data.items()}}


def check_owned(plan, secret):
    meta = metadata(secret)
    annotations = meta.get("annotations", {})
    if meta.get("namespace") != plan["namespace"] or meta.get("labels", {}).get("envplane.io/purpose") != "mysql-source-preparation" or annotations.get("envplane.io/preparation-digest") != plan["digest"] or annotations.get("envplane.io/source-uid") != plan["statefulSetUID"] or secret.get("immutable") is not True:
        raise Refused("Existing Secret is not immutable and owned by this preparation")


def prepared_template(plan, template):
    obj = copy.deepcopy(template)
    spec = obj["spec"]
    container = next(c for c in spec["containers"] if c["name"] == plan["container"])
    paths = {m["mountPath"] for m in container.get("volumeMounts", [])}
    if "/etc/envplane/mysql-tls" in paths or "/etc/mysql/conf.d/zz-envplane-source.cnf" in paths or any(v["name"] == "envplane-source-tls" for v in spec.get("volumes", [])):
        raise Refused("Reserved preparation mounts already exist")
    spec.setdefault("volumes", []).append({"name": "envplane-source-tls", "secret": {"secretName": plan["tlsSecret"], "defaultMode": 0o444}})
    container.setdefault("volumeMounts", []).extend([
        {"name": "envplane-source-tls", "mountPath": "/etc/envplane/mysql-tls", "readOnly": True},
        {"name": "envplane-source-tls", "mountPath": "/etc/mysql/conf.d/zz-envplane-source.cnf", "subPath": "source.cnf", "readOnly": True}])
    return obj


ROOT_COMMAND = ['sh', '-ec', 'test -n "$MYSQL_ROOT_PASSWORD"; export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysql --protocol=SOCKET --user=root --batch --skip-column-names --skip-reconnect --local-infile=0']


def pod_for(kube, plan):
    pods = json.loads(kube.call(["get", "pods", "-o", "json"]))["items"]
    matches = [p for p in pods if any(o.get("uid") == plan["statefulSetUID"] and o.get("kind") == "StatefulSet" and o.get("controller") is True for o in p.get("metadata", {}).get("ownerReferences", [])) and not p["metadata"].get("deletionTimestamp")]
    if len(matches) != 1 or not any(c.get("name") == plan["container"] and c.get("ready") is True for c in matches[0].get("status", {}).get("containerStatuses", [])):
        raise Refused("One owned Ready source Pod required")
    containers = matches[0].get("spec", {}).get("containers", [])
    if len(containers) != 1 or containers[0].get("name") != plan["container"] or containers[0].get("image") != plan["image"] or containers[0].get("command") or containers[0].get("args"):
        raise Refused("Source Pod does not match the approved container")
    root = [e for e in containers[0].get("env", []) if e.get("name") == "MYSQL_ROOT_PASSWORD"]
    if len(root) != 1 or root[0].get("valueFrom", {}).get("secretKeyRef", {}).get("name") != plan["rootSecret"] or root[0].get("valueFrom", {}).get("secretKeyRef", {}).get("key") != plan["rootPasswordKey"]:
        raise Refused("Source Pod administrator reference drifted")
    return matches[0]["metadata"]["name"]


def root_sql(kube, plan, sql):
    return kube.call(["exec", "-i", pod_for(kube, plan), "-c", plan["container"], "--"] + ROOT_COMMAND, sql.encode())


def apply(kube, plan, approve, allow_restart, allow_owner_change=False):
    canonical = {k: v for k, v in plan.items() if k != "digest"}
    if approve != plan.get("digest") or digest(canonical) != approve or not allow_restart:
        raise Refused("Exact reviewed digest and source restart approval required")
    # Validate bounded SQL/command identities before even a read-only root query.
    sql_create(plan, "a" * 64)
    for field in ("namespace", "statefulSet", "pvc", "service", "container", "rootSecret", "appSecret", "credentialSecret", "tlsSecret", "caSecret"):
        if not valid_name(plan[field]):
            raise Refused("Invalid reviewed source identity")
    if plan["tlsServerName"] != plan["service"] + "." + plan["namespace"] + ".svc":
        raise Refused("Invalid reviewed TLS endpoint")
    if plan.get("desiredStateOwner") and not allow_owner_change:
        raise Refused("Helm-owned source requires explicit desired-state owner change acknowledgement")
    sts, pvc, service = [kube.get(kind, plan[key]) for kind, key in (("statefulset", "statefulSet"), ("pvc", "pvc"), ("service", "service"))]
    cluster = json.loads(run(kube.prefix + ["get", "namespace", "kube-system", "-o", "json"]))
    for obj, field in ((cluster, "clusterUID"), (sts, "statefulSetUID"), (pvc, "pvcUID"), (service, "serviceUID")):
        if metadata(obj)["uid"] != plan[field]:
            raise Refused("Approved source identity changed")
    if kube.namespace != plan["namespace"] or pvc["spec"].get("volumeName") != plan["pv"]:
        raise Refused("Approved source namespace or backing volume changed")
    credentials = kube.optional_secret(plan["credentialSecret"])
    tls = kube.optional_secret(plan["tlsSecret"])
    ca = kube.optional_secret(plan["caSecret"])
    template = sts["spec"]["template"]
    already_configured = digest(template) != plan["sourceTemplateDigest"]
    if already_configured:
        if not tls:
            raise Refused("Source configuration drifted before preparation")
        check_owned(plan, tls)
        if digest(template) != tls["metadata"]["annotations"].get("envplane.io/prepared-template-digest"):
            raise Refused("Prepared source configuration drifted; no changes made")
    else:
        rebuilt = plan_for(cluster, sts, pvc, service, plan["tenant"], plan["project"])
        if rebuilt != plan:
            raise Refused("Reviewed source configuration changed")
    if not root_sql(kube, plan, "SELECT VERSION();\n").decode().strip().startswith(("8.0.", "8.4.")):
        raise Refused("Unsupported running MySQL version")
    exists = root_sql(kube, plan, "SELECT COUNT(*) FROM mysql.user WHERE User='" + plan["backupUsername"] + "';\n").strip()
    if exists not in (b"0", b"1") or (exists == b"1" and not credentials):
        raise Refused("Backup account collision; no account adopted")
    if credentials:
        check_owned(plan, credentials)
        password = base64.b64decode(credentials["data"]["password"], validate=True).decode()
        if base64.b64decode(credentials["data"]["username"]).decode() != plan["backupUsername"]:
            raise Refused("Owned backup credential identity changed")
    else:
        password = secrets.token_hex(32)
        credentials = kube.create(owned_secret(plan, plan["credentialSecret"], {"username": plan["backupUsername"].encode(), "password": password.encode()}))
    sql_create(plan, password)  # Validate even on retries.
    if not already_configured:
        prepared = prepared_template(plan, template)
        if tls:
            check_owned(plan, tls)
            if tls["metadata"]["annotations"].get("envplane.io/prepared-template-digest") != digest(prepared):
                raise Refused("TLS preparation identity drift")
        else:
            material = tls_material(plan)
            material["source.cnf"] = b"[mysqld]\nssl_ca=/etc/envplane/mysql-tls/ca.pem\nssl_cert=/etc/envplane/mysql-tls/server.pem\nssl_key=/etc/envplane/mysql-tls/server.key\ntls_version=TLSv1.2,TLSv1.3\n"
            tls = kube.create(owned_secret(plan, plan["tlsSecret"], material, {"envplane.io/prepared-template-digest": digest(prepared)}))
        if ca:
            check_owned(plan, ca)
            if ca.get("data") != {"ca.crt": tls["data"]["ca.pem"]}:
                raise Refused("Public CA reference drift")
        else:
            ca = kube.create(owned_secret(plan, plan["caSecret"], {"ca.crt": base64.b64decode(tls["data"]["ca.pem"], validate=True)}))
        patch = [{"op": "test", "path": "/metadata/uid", "value": plan["statefulSetUID"]},
                 {"op": "test", "path": "/metadata/resourceVersion", "value": sts["metadata"]["resourceVersion"]},
                 {"op": "replace", "path": "/spec/template", "value": prepared}]
        kube.call(["patch", "statefulset", plan["statefulSet"], "--type=json", "--patch-file=/dev/stdin"], json.dumps(patch).encode())
    if ca is None:
        raise Refused("Public CA receipt missing; preparation needs operator recovery")
    check_owned(plan, ca)
    if ca.get("data") != {"ca.crt": tls["data"]["ca.pem"]}:
        raise Refused("Public CA reference drift")
    kube.call(["rollout", "status", "statefulset/" + plan["statefulSet"], "--timeout=180s"], timeout=190)
    if exists == b"0":
        root_sql(kube, plan, sql_create(plan, password))
    # No ALTER USER, account adoption or privilege repair on retry. A partial
    # GRANT failure must be reviewed; we never silently widen an existing user.
    ssl_requirement = root_sql(kube, plan, "SELECT ssl_type FROM mysql.user WHERE User='" + plan["backupUsername"] + "' AND Host='%';\n").strip()
    if ssl_requirement != b"ANY":
        raise Refused("Dedicated backup account must require SSL")
    verify(kube, plan, password)
    final_sts, final_pvc, final_service = [kube.get(kind, plan[key]) for kind, key in (("statefulset", "statefulSet"), ("pvc", "pvc"), ("service", "service"))]
    if metadata(final_sts)["uid"] != plan["statefulSetUID"] or digest(final_sts["spec"]["template"]) != tls["metadata"]["annotations"]["envplane.io/prepared-template-digest"] or metadata(final_pvc)["uid"] != plan["pvcUID"] or final_pvc["spec"].get("volumeName") != plan["pv"] or metadata(final_service)["uid"] != plan["serviceUID"] or digest(final_service["spec"]) != plan["serviceSpecDigest"]:
        raise Refused("Source drifted during preparation; verification receipt refused")
    return {"status": "verified", "planDigest": approve, "sourceRestarted": not already_configured,
            "backupSecretName": plan["credentialSecret"], "backupUsername": plan["backupUsername"], "backupPasswordKey": "password",
            "caSecretName": plan["caSecret"], "caKey": "ca.crt", "tlsServerName": plan["tlsServerName"],
            "credentialsPrinted": False, "sourcePVC": plan["pvc"], "copyProfileApprovalStillRequired": True,
            "desiredStateReconciliationRequired": bool(plan.get("desiredStateOwner"))}


def verify(kube, plan, password):
    # The client config travels only over exec stdin into an owner-only tmp file.
    # MySQL errors/results are never surfaced in CLI diagnostics.
    config = ("[client]\nuser=" + plan["backupUsername"] + "\npassword=" + password + "\n").encode()
    script = ['sh', '-ec', 'umask 077; f=$(mktemp /tmp/ep-mysql-client.XXXXXX); trap \'rm -f "$f"\' EXIT; cat > "$f"; mysql --defaults-extra-file="$f" --protocol=TCP --host="$1" --port=3306 --ssl-mode=VERIFY_IDENTITY --ssl-ca=/etc/envplane/mysql-tls/ca.pem --batch --skip-column-names --local-infile=0 --execute="SHOW STATUS LIKE \'Ssl_cipher\'; SHOW GRANTS; LOCK INSTANCE FOR BACKUP; UNLOCK INSTANCE;"', 'verify', plan["tlsServerName"]]
    output = kube.call(["exec", "-i", pod_for(kube, plan), "-c", plan["container"], "--"] + script, config)
    rows = output.decode().splitlines()
    if not rows or not re.fullmatch(r"Ssl_cipher\s+\S+", rows[0]):
        raise Refused("Verified TLS session unavailable")
    validate_grants(plan, rows[1:])


def validate_grants(plan, rows):
    scopes = {"*.*": {"USAGE", "SHOW_ROUTINE", "BACKUP_ADMIN"}, "`" + plan["database"] + "`.*": {"SELECT", "SHOW VIEW", "TRIGGER", "EVENT"}}
    observed = {key: set() for key in scopes}
    users = {"`" + plan["backupUsername"] + "`@`%`", "'" + plan["backupUsername"] + "'@'%'"}
    for row in rows:
        match = re.fullmatch(r"GRANT (.+) ON (.+) TO (.+)", row)
        if not match or match[2] not in scopes or match[3] not in users:
            raise Refused("Unexpected grant scope, role, account or grant option")
        permissions = {value.strip() for value in match[1].split(",")}
        if not permissions or not permissions.issubset(scopes[match[2]]):
            raise Refused("Backup account has unexpected excessive privileges")
        observed[match[2]].update(permissions)
    if not {"SHOW_ROUTINE", "BACKUP_ADMIN"}.issubset(observed["*.*"]) or observed["`" + plan["database"] + "`.*"] != scopes["`" + plan["database"] + "`.*"]:
        raise Refused("Dedicated backup privileges not verified")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("preview", "apply"))
    for flag in ("kubeconfig", "context", "namespace"):
        parser.add_argument("--" + flag, required=True)
    for flag in ("statefulset", "pvc", "service", "tenant", "project", "plan", "approve-plan"):
        parser.add_argument("--" + flag)
    parser.add_argument("--allow-source-restart", action="store_true")
    parser.add_argument("--allow-reconciled-workload-change", action="store_true")
    args = parser.parse_args(argv)
    if not valid_name(args.namespace):
        raise Refused("Exact source namespace required")
    kube = Kubernetes(args.kubeconfig, args.context, args.namespace)
    if args.mode == "preview":
        if not all((args.statefulset, args.pvc, args.service, args.tenant, args.project)):
            raise Refused("Explicit source and ownership scope required")
        cluster = json.loads(run(kube.prefix + ["get", "namespace", "kube-system", "-o", "json"]))
        plan = plan_for(cluster, kube.get("statefulset", args.statefulset), kube.get("pvc", args.pvc), kube.get("service", args.service), args.tenant, args.project)
        print(json.dumps(plan, indent=2))
    else:
        if not args.plan or not args.approve_plan:
            raise Refused("Reviewed plan file and digest required")
        path = Path(args.plan)
        if not path.is_file() or path.stat().st_size > 65536:
            raise Refused("Bounded reviewed plan file required")
        plan = json.loads(path.read_text())
        print(json.dumps(apply(kube, plan, args.approve_plan, args.allow_source_restart, args.allow_reconciled_workload_change), indent=2))


if __name__ == "__main__":
    try:
        main()
    except Refused as error:
        print(str(error) + ". No credentials printed; retain owned Secrets for reviewed recovery. No automatic source rollback or deletion.", file=sys.stderr)
        sys.exit(1)
    except (ValueError, KeyError, TypeError, OSError, StopIteration):
        print("MySQL preparation refused or incomplete. No credentials printed. Retain owned Secrets for reviewed recovery; no automatic source rollback or deletion.", file=sys.stderr)
        sys.exit(1)
