"""Render-only contract tests; no cluster or host filesystem mutations."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / "deploy/helm/envplane-storage-verifier"


class StorageVerifierChartTest(unittest.TestCase):
    def render(self, *extra):
        args = ["helm", "template", "test", str(CHART)]
        args.extend(extra)
        return subprocess.run(args, text=True, capture_output=True, check=False)

    def configured(self, *extra):
        values = {
            "enabled": "true", "allowReadOnlyHostPath": "true",
            "nodeName": "node-a", "tenantId": "tenant-a", "clusterId": "cluster-a",
            "clusterGeneration": "1", "image.tag": "0.1.0",
            "existingTLSSecret": "tls", "existingClientCASecret": "ca",
            "existingSigningSecret": "signing", "signingKeyId": "signer-1",
        }
        options = []
        for key, value in values.items():
            options.extend(["--set", f"{key}={value}"])
        return self.render(*options, *extra)

    def test_disabled_by_default(self):
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("kind:", result.stdout)

    def test_explicit_administrator_approval_required(self):
        result = self.render("--set", "enabled=true")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("administrator approval", result.stderr)

    def test_exact_image_and_bounded_roots(self):
        for args in [("--set", "image.tag=latest"),
                     ("--set", "clusterGeneration=0"),
                     ("--set", "roots[0].originalRoot=/"),
                     ("--set", "roots[0].mountRoot=/host-storage/../escape")]:
            result = self.configured(*args)
            self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_separate_read_only_privileges_and_persistent_inventory(self):
        result = self.configured()
        self.assertEqual(result.returncode, 0, result.stderr)
        text = result.stdout
        self.assertIn("verbs: [get, list, watch]", text)
        for unsafe in ["pods/exec", "pods/log", "secrets]", "privileged: true",
                       "hostNetwork: true", "hostPID: true", "type: DirectoryOrCreate"]:
            self.assertNotIn(unsafe, text)
        self.assertIn("nodeName: \"node-a\"", text)
        self.assertIn("--inventory-file=/var/lib/storage-verifier/state/inventory.json", text)
        self.assertIn("helm.sh/resource-policy: keep", text)
        self.assertIn("capabilities: {drop: [ALL]}", text)
        self.assertIn('mountPath: "/host-storage/local-path", readOnly: true', text)
        self.assertIn('mountPath: "/host-storage/minikube", readOnly: true', text)
        self.assertIn("--client-ca-file=/client-ca/ca.crt", text)


if __name__ == "__main__":
    unittest.main()
