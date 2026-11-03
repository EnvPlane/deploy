import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

spec = importlib.util.spec_from_file_location("diagnostics", Path(__file__).parents[1] / "sm09-control-plane-diagnostics.py")
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)


class DiagnosticsTests(unittest.TestCase):
    def test_all_replicas_and_previous_logs_without_secret_values(self):
        calls = []
        secret = "do-not-print-this-credential"

        def run(args, **kwargs):
            calls.append(args)
            if "get" in args:
                pods = [{"metadata": {"name": name}, "status": {"containerStatuses": [{
                    "name": "api", "ready": name == "old", "restartCount": 7,
                    "state": {"waiting": {"reason": "CrashLoopBackOff", "message": secret}},
                    "lastState": {"terminated": {"exitCode": 1, "message": secret}},
                }]}} for name in ("old", "new")]
                return subprocess.CompletedProcess(args, 0, json.dumps({"items": pods}), secret)
            if "new" in args and "--previous" in args:
                raw = json.dumps({"level": "ERROR", "msg": "failed to ping postgres",
                                  "error": f"postgres://user:{secret}@db SQLSTATE 28P01"})
            else:
                raw = json.dumps({"level": "INFO", "msg": secret})
            return subprocess.CompletedProcess(args, 0, raw, secret)

        output = diagnostics.collect("fixture", "fixture", run)
        self.assertEqual({x["pod"] for x in output}, {"old", "new"})
        self.assertIn({"pod": "new", "log": "previous", "category": "postgres_connect", "sqlstate": "28P01"}, output)
        self.assertEqual(sum("logs" in x for x in calls), 4)
        self.assertNotIn(secret, json.dumps(output))
        self.assertEqual([x["lastStateExitCode"] for x in output if "lastStateExitCode" in x], [1, 1])

    def test_arbitrary_errors_and_non_json_are_not_printed(self):
        raw = '\n'.join(["password=fixture-secret", "panic: fixture-secret", json.dumps({"level": "ERROR", "message": "fixture-secret", "error": "fixture-secret"})])
        records = diagnostics.startup_records(raw)
        self.assertEqual({x["category"] for x in records}, {"panic", "unclassified_error"})
        self.assertNotIn("fixture-secret", json.dumps(records))

    def test_unavailable_inventory_is_bounded(self):
        def run(args, **kwargs):
            self.assertEqual(kwargs["timeout"], 15)
            return subprocess.CompletedProcess(args, 1, "", "credential=fixture-secret")
        self.assertEqual(diagnostics.collect("fixture", "fixture", run), [{"diagnostics": "pod_inventory_unavailable"}])

    def test_config_error_classification_omits_path_and_credentials(self):
        raw = json.dumps({"level": "ERROR", "msg": "failed to load runtime config",
                          "error": "read install-flow compatibility manifest: /private/fixture-secret: denied"})
        self.assertEqual(diagnostics.startup_records(raw), [{
            "category": "runtime_config", "sqlstate": "",
            "configChecks": ["compatibility_manifest_read"],
        }])

    def test_identity_collision_is_classified_without_custody_material(self):
        raw = json.dumps({"level": "ERROR", "msg": "failed to initialise offline license store",
                          "error": "installation_identity_in_use; fixture-secret"})
        self.assertEqual(diagnostics.startup_records(raw), [{
            "category": "license_store", "sqlstate": "",
            "configChecks": ["installation_identity_in_use"],
        }])


if __name__ == "__main__":
    unittest.main()
