import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

PATH = Path(__file__).resolve().parents[1] / "scoped-data-migration.py"
SPEC = importlib.util.spec_from_file_location("migration", PATH)
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class ScopedMigrationTests(unittest.TestCase):
    def setUp(self):
        self.plan = {"source": "source", "target": "candidate", "sourceUID": "s", "targetUID": "t", "flux": [],
                     "namespaces": [{"identity": {"name": "app-backend", "uid": "ns"}, "pvcs": [
                         {"name": "backend-data", "uid": "claim", "volume": {"name": "old-pv"},
                          "storageClass": "standard", "accessModes": ["ReadWriteOnce"], "capacity": "1Gi"}]}]}

    def test_operation_requires_explicit_gate_hash_and_scope(self):
        with patch.object(m, "get") as get:
            for coordinated, sha, ns, claim in ((False, m.digest(self.plan), "app-backend", "backend-data"),
                                               (True, "bad", "app-backend", "backend-data"),
                                               (True, m.digest(self.plan), "envplane-system", "auth")):
                with self.assertRaises(ValueError):
                    m.authorize(self.plan, sha, ns, claim, coordinated)
            get.assert_not_called()

    def test_uid_and_pvc_binding_drift(self):
        def get(context, kind, namespace=None):
            if kind == "namespace/kube-system": return {"metadata": {"uid": "s" if context == "source" else "t"}}
            if kind.startswith("namespace/"): return {"metadata": {"uid": "ns"}}
            return {"metadata": {"uid": "claim"}, "spec": {"volumeName": "wrong-pv"}}
        with patch.object(m, "get", side_effect=get):
            with self.assertRaises(ValueError):
                m.authorize(self.plan, m.digest(self.plan), "app-backend", "backend-data", True)

    def test_target_pvc_never_reuses_old_volume_binding(self):
        image = "example/helper@sha256:" + "a" * 64
        output = m.render_helper(self.plan, "app-backend", "backend-data", "target", image, "standard")
        self.assertNotIn("volumeName", output["pvc"]["spec"])
        self.assertNotIn("uid", output["pvc"]["metadata"])
        self.assertNotIn("old-pv", str(output))
        self.assertFalse(output["pod"]["spec"]["automountServiceAccountToken"])
        self.assertEqual(output["context"], "candidate")
        with self.assertRaises(ValueError):
            m.render_helper(self.plan, "app-backend", "backend-data", "target", "helper:latest", "standard")
        with self.assertRaises(ValueError):
            m.render_helper(self.plan, "app-backend", "backend-data", "target", image)

    def test_source_helper_read_only_and_quiesced_claim_required(self):
        output = m.render_helper(self.plan, "app-backend", "backend-data", "source", "helper@sha256:" + "a" * 64)
        self.assertTrue(output["pod"]["spec"]["containers"][0]["volumeMounts"][0]["readOnly"])
        self.assertNotIn("pvc", output)
        pods = {"items": [{"metadata": {"name": "mysql-0"}, "spec": {"volumes": [
            {"persistentVolumeClaim": {"claimName": "backend-data"}}]}, "status": {"phase": "Running"}}]}
        with patch.object(m, "get", return_value=pods):
            with self.assertRaises(ValueError):
                m.quiesced_claim("source", "app-backend", "backend-data", "migration-helper")

    def test_unsuspended_flux_blocks_stream_before_transfer(self):
        plan = dict(self.plan, flux=[{"name": "shared-root", "namespace": "flux-system", "uid": "f"}])
        with patch.object(m, "get", return_value={"metadata": {"uid": "f"}, "spec": {"suspend": False}}):
            with self.assertRaises(ValueError):
                m.frozen(plan, "app-backend")

    def test_credentials_are_not_argv_values(self):
        args = m.mysql_command(["kubectl", "exec", "mysql-0", "--"], "dump")
        self.assertNotIn("-p", args)
        self.assertIn('$MYSQL_ROOT_PASSWORD', args[-1])
        self.assertIn("--single-transaction", args[-1])
        self.assertNotIn("--all-databases", args[-1])

    def test_archive_exclusive_private_and_streaming_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "plan.json"
            m.write_private(path, self.plan)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError): m.write_private(path, {})
            self.assertEqual(len(m.file_digest(path)), 64)

    def test_restricted_helper_uses_reviewed_identity_without_fsgroup_chown(self):
        result = m.render_helper(self.plan, "app-backend", "backend-data", "source", "helper@sha256:" + "a" * 64,
                                 uid=65532, gid=65532)
        security = result["pod"]["spec"]["securityContext"]
        self.assertTrue(security["runAsNonRoot"])
        self.assertEqual(security["runAsUser"], 65532)
        self.assertEqual(security["seccompProfile"]["type"], "RuntimeDefault")
        self.assertNotIn("fsGroup", security)
        container = result["pod"]["spec"]["containers"][0]["securityContext"]
        self.assertFalse(container["allowPrivilegeEscalation"])
        self.assertEqual(container["capabilities"]["drop"], ["ALL"])
        self.assertNotIn("add", container["capabilities"])


if __name__ == "__main__":
    unittest.main()
