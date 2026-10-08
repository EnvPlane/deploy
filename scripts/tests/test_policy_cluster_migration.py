import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "plan-policy-cluster-migration.py"
SPEC = importlib.util.spec_from_file_location("migration", SCRIPT)
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.snapshot = {"context": "bethunder-local", "clusterIdentity": {"uid": "source-uid"}}
        self.plan = m.make_plan("bethunder-local", "envplane-policy-candidate", "v1.35.1", self.snapshot)

    def test_same_target_and_unpinned_version_rejected(self):
        for target, version in (("bethunder-local", "v1.35.1"), ("../evil", "v1.35.1"),
                                ("new", "latest"), ("new", "v1.35")):
            with self.assertRaises(ValueError):
                m.make_plan("bethunder-local", target, version, self.snapshot)

    def test_inventory_is_redacted(self):
        def get(context, resource, namespace=None):
            if resource == "namespace/kube-system":
                return {"metadata": {"name": "kube-system", "uid": "source"}}
            return {"items": [{"metadata": {"name": "app-backend", "uid": "x",
                                           "annotations": {"private": "SECRET"}},
                                "spec": {"containers": [{"image": "example:v1", "env": ["SECRET"]}],
                                         "secret": "SECRET"}}]}
        with patch.object(m, "get", side_effect=get):
            report = m.inventory("test")
        self.assertNotIn("SECRET", json.dumps(report))
        self.assertIn("example:v1", json.dumps(report))

    def test_private_exclusive_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "inventory.json"
            m.write_private(path, self.snapshot)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                m.write_private(path, {})
            link = Path(directory) / "symlink"
            link.symlink_to(path)
            with self.assertRaises(FileExistsError):
                m.write_private(link, {})

    def test_apply_rejects_unapproved_or_tampered_plan(self):
        with patch.object(m, "command") as command:
            for sha, target in (("wrong", self.plan["targetProfile"]), (m.digest(self.plan), "wrong")):
                with self.assertRaises(ValueError):
                    m.execute_plan(self.plan, self.snapshot, sha, target)
            altered = dict(self.plan, command=["kubectl", "delete", "namespace", "app-backend"])
            with self.assertRaises(ValueError):
                m.execute_plan(altered, self.snapshot, m.digest(altered), altered["targetProfile"])
            command.assert_not_called()

    def test_stopped_or_invalid_profile_collision(self):
        with patch.object(m, "profiles", return_value={self.plan["targetProfile"]}), \
                patch.object(m, "command") as command:
            with self.assertRaises(ValueError):
                m.execute_plan(self.plan, self.snapshot, m.digest(self.plan), self.plan["targetProfile"])
            command.assert_not_called()

    def test_profile_inventory_fails_closed(self):
        for result in ("{}", '{"valid": null}', "not json"):
            with patch.object(m, "command", return_value=result):
                with self.assertRaises(ValueError):
                    m.profiles()
        with patch.object(m, "command", return_value='{"valid": [], "invalid": [{"Name": "stopped"}]}'):
            self.assertEqual(m.profiles(), {"stopped"})

    def test_inventory_failure_and_drift_block_apply(self):
        for fresh in ({"context": "changed"}, None):
            with patch.object(m, "profiles", return_value=set()), \
                    patch.object(m, "inventory", return_value=fresh, side_effect=ValueError() if fresh is None else None), \
                    patch.object(m, "command") as command:
                with self.assertRaises(ValueError):
                    m.execute_plan(self.plan, self.snapshot, m.digest(self.plan), self.plan["targetProfile"])
                command.assert_not_called()

    def test_existing_kube_context_blocks_apply(self):
        with patch.object(m, "profiles", return_value=set()), \
                patch.object(m, "inventory", return_value=dict(self.snapshot)), \
                patch.object(m, "command", return_value=self.plan["targetProfile"] + "\n") as command:
            with self.assertRaises(ValueError):
                m.execute_plan(self.plan, self.snapshot, m.digest(self.plan), self.plan["targetProfile"])
            self.assertEqual(command.call_count, 1)

    def test_only_new_cluster_command_runs_no_cutover(self):
        with patch.object(m, "profiles", return_value=set()), \
                patch.object(m, "inventory", return_value=dict(self.snapshot)), \
                patch.object(m, "command", return_value="source-context\n") as command:
            m.execute_plan(self.plan, self.snapshot, m.digest(self.plan), self.plan["targetProfile"])
        self.assertEqual(command.call_args_list[-1].args[0], self.plan["command"])
        self.assertEqual(command.call_count, 2)
        self.assertIn("--cni=calico", self.plan["command"])

    def test_zero_setup_pins_policy_capable_cni_only_for_new_profile(self):
        script = (SCRIPT.parent / "minikube-up.sh").read_text()
        self.assertIn("--cni=calico", script)
        self.assertLess(script.index("minikube profile list"), script.index("--cni=calico"))


if __name__ == "__main__":
    unittest.main()
