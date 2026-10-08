import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


def load(name):
    path = Path(__file__).resolve().parents[1] / (name + ".py")
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bridge = load("flux-restricted-policy-bridge")
mysql = load("reconcile-restored-mysql-credential")
snapshot = load("scoped-config-snapshot")


class FluxBridgeReviewTests(unittest.TestCase):
    def run_bridge(self, same_namespace=False, custom=False, suspended=True):
        writes = []
        policy = {"metadata": {"uid": "policy", "resourceVersion": "7"}, "spec": {
            "podSelector": {}, "policyTypes": ["Egress"], "egress": [
                {"to": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "app-base"}}}]}]}}
        if same_namespace:
            policy["spec"]["egress"].append({"to": [{"podSelector": {}}]})
        def call(context, args, data=None):
            self.assertEqual(context, "candidate")
            if "get" in args:
                if "networkpolicy" in args:
                    return json.dumps(policy).encode()
                return json.dumps({"metadata": {"uid": args[4], "resourceVersion": "11"},
                                   "spec": {"suspend": suspended, "patches": [{"unknown": True}] if custom else []}}).encode()
            writes.append((args, json.loads(data)))
            return b""
        argv = ["bridge", "--context", "candidate", "--approve-target", "candidate", "--namespace", "envplane-pr-reviewed",
                "--root", "root", "--feature", "feature", "--base-namespace", "app-base"]
        with patch("sys.argv", argv), patch.object(bridge, "call", side_effect=call), contextlib.redirect_stdout(io.StringIO()):
            try:
                bridge.main()
            except ValueError:
                self.assertFalse(writes, "review failure must occur before mutations")
                raise
        return writes

    def test_bridge_scopes_nested_target_and_uses_identity_preconditions(self):
        writes = self.run_bridge()
        self.assertEqual(len(writes), 3)
        root = writes[0][1]
        self.assertEqual([op["path"] for op in root[:3]], ["/metadata/uid", "/metadata/resourceVersion", "/spec/suspend"])
        self.assertEqual(root[-1]["value"][0]["target"]["namespace"], "flux-system")
        policy = writes[-1][1]
        self.assertEqual(policy[-1]["value"], {"to": [{"podSelector": {}}]})
        selector = next(op["value"] for op in policy if op["path"] == "/spec/podSelector")
        self.assertEqual(selector["matchExpressions"][0]["operator"], "DoesNotExist")
        self.assertFalse(any("deny-all" in str(args) for args, _ in writes))

    def test_existing_allow_is_not_duplicated(self):
        writes = self.run_bridge(same_namespace=True)
        self.assertFalse(any(op["path"] == "/spec/egress/-" for op in writes[-1][1]))

    def test_custom_patches_or_active_flux_reject_before_write(self):
        for kwargs in ({"custom": True}, {"suspended": False}):
            with self.assertRaises(ValueError):
                self.run_bridge(**kwargs)


class MySQLCredentialReviewTests(unittest.TestCase):
    def fixtures(self, cleanup=False):
        container = {"name": "mysql", "env": [{"name": "MYSQL_USER", "value": "app_user"},
                     {"name": "MYSQL_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "current", "key": "password"}}}]}
        obj = {"metadata": {"uid": "database-uid", "resourceVersion": "4"},
               "spec": {"template": {"spec": {"containers": [container]}}}}
        secret = {"metadata": {"uid": "secret-uid", "resourceVersion": "8", "labels": {
            "envplane.io/purpose": "candidate-credential-reconciliation", "envplane.io/mysql-statefulset-uid": "database-uid"}},
            "data": {"password": base64.b64encode(b"TEST_ONLY_PASSWORD").decode()}}
        if cleanup:
            container["args"] = ["--init-file=/var/run/envplane-migration/mysql-init.sql"]
            container["volumeMounts"] = [{"name": "migration-db-credential-init", "mountPath": "/var/run/envplane-migration", "readOnly": True}]
            obj["spec"]["template"]["spec"]["volumes"] = [{"name": "migration-db-credential-init", "secret": {"secretName": "envplane-migration-mysql-reconcile"}}]
        return obj, secret

    def run_mysql(self, mode, owned=True, rollout_ok=True, restored=True):
        obj, secret = self.fixtures(cleanup=mode == "cleanup")
        if not owned:
            secret["metadata"]["labels"] = {}
        calls, output = [], io.StringIO()
        def call(context, namespace, args, data=None):
            self.assertEqual((context, namespace), ("candidate", "feature"))
            calls.append((args, json.loads(data) if data else None))
            if args[:2] == ["get", "statefulset"]:
                return json.dumps(obj).encode()
            if args[:2] == ["get", "secret"]:
                return json.dumps(secret).encode()
            if args[0] == "rollout" and not rollout_ok:
                raise ValueError("rollout failed")
            return b""
        ledger = {"source": "old-source", "target": "candidate", "claims": [{"namespace": "feature", "claim": "mysql-data", "restored": restored}]}
        argv = ["mysql", "--context", "candidate", "--namespace", "feature", "--authorize-namespace", "feature",
                "--integrity-ledger", "private-ledger", mode]
        with patch("sys.argv", argv), patch.object(Path, "read_text", return_value=json.dumps(ledger)), \
                patch.object(mysql, "call", side_effect=call), contextlib.redirect_stdout(output):
            try:
                mysql.main()
            except ValueError:
                self.assertFalse(any(args[0] == "delete" for args, _ in calls))
                if not owned or restored is not True:
                    self.assertFalse(any(args[0] in ("create", "patch") for args, _ in calls))
                raise
        self.assertNotIn("TEST_ONLY_PASSWORD", output.getvalue())
        return calls

    def test_prepare_uses_current_secret_and_no_grant_bypass(self):
        calls = self.run_mysql("prepare")
        payload = next(data for args, data in calls if args[0] == "create")
        sql = base64.b64decode(payload["data"]["mysql-init.sql"]).decode()
        self.assertTrue(sql.startswith("ALTER USER 'app_user'@'%' IDENTIFIED BY "))
        self.assertNotIn("GRANT", sql)
        self.assertEqual(payload["metadata"]["labels"]["envplane.io/mysql-statefulset-uid"], "database-uid")
        ops = next(data for args, data in calls if args[0] == "patch")
        self.assertEqual(ops[0]["path"], "/metadata/uid")
        self.assertNotIn("skip-grant-tables", str(calls))

    def test_cleanup_waits_and_deletes_only_preconditioned_owned_secret(self):
        calls = self.run_mysql("cleanup")
        order = [args[0] for args, _ in calls]
        self.assertLess(order.index("rollout"), order.index("delete"))
        deletion = next(data for args, data in calls if args[0] == "delete")
        self.assertEqual(deletion["preconditions"], {"uid": "secret-uid", "resourceVersion": "8"})

    def test_unowned_secret_failed_rollout_and_truthy_false_are_not_deleted(self):
        for kwargs in ({"owned": False}, {"rollout_ok": False}, {"restored": "false"}):
            with self.assertRaises(ValueError):
                self.run_mysql("cleanup", **kwargs)


class SnapshotScopeReviewTests(unittest.TestCase):
    def test_mixed_cluster_binding_does_not_import_unapproved_subject(self):
        def get(context, kind, namespace=None):
            if kind.startswith("namespace/"):
                return {"kind": "Namespace", "metadata": {"name": kind.split("/")[1], "uid": context}}
            if kind == "serviceaccounts":
                return {"items": [{"kind": "ServiceAccount", "metadata": {"name": "worker", "namespace": namespace}}]}
            if kind == "clusterrolebindings":
                return {"items": [{"kind": "ClusterRoleBinding", "metadata": {"name": "mixed"},
                         "roleRef": {"name": "unapproved-role"}, "subjects": [
                             {"kind": "ServiceAccount", "name": "worker", "namespace": "envplane-system"},
                             {"kind": "ServiceAccount", "name": "other", "namespace": "outside"}]}]}
            if kind.startswith("clusterrole/"):
                self.fail("unapproved mixed-subject role must not be fetched")
            return {"items": []}
        captured = []
        def encrypt(args, **kwargs):
            captured.append(json.loads(kwargs["input"]))
            return subprocess.CompletedProcess(args, 0)
        with tempfile.TemporaryDirectory() as directory, patch.object(snapshot, "get", side_effect=get), \
                patch.object(snapshot.subprocess, "run", side_effect=encrypt), contextlib.redirect_stdout(io.StringIO()):
            snapshot.snapshot("source", "candidate", ["envplane-system"], "age1test", str(Path(directory) / "archive"))
        self.assertFalse(any(o["kind"] == "ClusterRoleBinding" for o in captured[0]["objects"]))

    def test_invalid_restore_scope_is_validated_before_any_apply(self):
        objects = [{"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": "approved"}},
                   {"apiVersion": "v1", "kind": "Secret", "metadata": {"name": "unrelated", "namespace": "outside"}}]
        bundle = {"source": "source", "target": "candidate", "sourceUID": "s", "targetUID": "t", "namespaces": ["approved"], "objects": objects}
        with patch.object(snapshot, "sha", return_value="hash"), patch.object(snapshot.os, "stat") as stat, \
                patch.object(snapshot.os.path, "islink", return_value=False), \
                patch.object(snapshot, "command", return_value=json.dumps(bundle).encode()) as command:
            stat.return_value.st_mode = 0o600
            with self.assertRaises(ValueError):
                snapshot.restore("archive", "hash", "identity", "candidate", "candidate")
            self.assertEqual(command.call_count, 1, "decrypt is allowed, apply is not")

    def test_restore_rejects_active_workloads_tokens_duplicate_and_cluster_subject_escape(self):
        for obj in ({"kind": "Deployment", "metadata": {"name": "app", "namespace": "approved"}, "spec": {"replicas": 1}},
                    {"kind": "Secret", "metadata": {"name": "token", "namespace": "approved"}, "type": "kubernetes.io/service-account-token"},
                    {"kind": "ClusterRoleBinding", "metadata": {"name": "mixed"}, "subjects": [{"kind": "ServiceAccount", "namespace": "outside"}]}):
            with self.assertRaises(ValueError):
                snapshot.validate_bundle({"namespaces": ["approved"], "objects": [obj]})

    def test_component_label_uses_mount_not_claim_name_and_scope_does_not_export_flux(self):
        requests = []
        def get(context, kind, namespace=None):
            requests.append((kind, namespace))
            if kind.startswith("namespace/"):
                return {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": kind.split("/")[1], "uid": context}}
            if kind == "persistentvolumeclaims":
                return {"items": [{"apiVersion": "v1", "kind": "PersistentVolumeClaim", "metadata": {"name": "mysql-sounding-name", "namespace": namespace}, "spec": {"volumeName": "old"}}]}
            if kind == "deployments":
                return {"items": [{"kind": "Deployment", "metadata": {"name": "backend", "namespace": namespace}, "spec": {"replicas": 1, "template": {
                    "metadata": {"labels": {"app.kubernetes.io/component": "actual-backend"}},
                    "spec": {"volumes": [{"name": "storage", "persistentVolumeClaim": {"claimName": "mysql-sounding-name"}}],
                             "containers": [{"name": "backend", "volumeMounts": [{"name": "storage"}]}]}}}}]}
            return {"items": []}
        captured = []
        def encrypt(args, **kwargs):
            captured.append(json.loads(kwargs["input"]))
            return subprocess.CompletedProcess(args, 0)
        with tempfile.TemporaryDirectory() as directory, patch.object(snapshot, "get", side_effect=get), \
                patch.object(snapshot.subprocess, "run", side_effect=encrypt), contextlib.redirect_stdout(io.StringIO()):
            snapshot.snapshot("source", "candidate", ["app-backend"], "age1public-test", str(Path(directory) / "archive"))
        claim = next(o for o in captured[0]["objects"] if o["kind"] == "PersistentVolumeClaim")
        self.assertEqual(claim["metadata"]["labels"]["app.kubernetes.io/component"], "actual-backend")
        self.assertFalse(any(ns == "flux-system" for _, ns in requests))


if __name__ == "__main__":
    unittest.main()
