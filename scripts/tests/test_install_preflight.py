"""Reproduce denied platform permissions against a deterministic CLI boundary."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "envplane-install-preflight.sh"
STUB = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]
if a[:1]==['--context']: a=a[2:]
with open(os.environ['PREFLIGHT_LOG'],'a') as f: f.write(json.dumps(a)+'\\n')
if Path(sys.argv[0]).name=='helm':
 assert json.loads(Path(os.environ['HELM_REGISTRY_CONFIG']).read_text())=={'auths':{}}
 assert json.loads((Path(os.environ['DOCKER_CONFIG'])/'config.json').read_text())=={'auths':{}}
 sys.exit(0)
if a[:2]==['auth','can-i']:
 # Unknown resource strings simulate an admin's misleading yes; the exact
 # denied known permission must still make the diagnostic fail closed.
 denied=' '.join(a[2:4])==os.environ.get('PREFLIGHT_DENY','')
 print('no' if denied else 'yes');sys.exit(1 if denied else 0)
if a[:2]==['get','storageclass']: print('standard')
'''


class PreflightTests(unittest.TestCase):
    def invoke(self, deny="", version="0.4.731", namespace="envplane"):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ["kubectl", "helm"]:
                path = root / name
                path.write_text(STUB)
                path.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                       PREFLIGHT_LOG=str(root / "log"), PREFLIGHT_DENY=deny)
            result = subprocess.run(["bash", str(SCRIPT), "--version", version,
                                     "--namespace", namespace, "--kube-context", "envplane"],
                                    capture_output=True, text=True, env=env)
            calls = [json.loads(line) for line in (root / "log").read_text().splitlines()] if (root / "log").exists() else []
            return result, calls

    def test_denied_cluster_permissions_fail_closed(self):
        for permission in ["create clusterroles.rbac.authorization.k8s.io",
                           "create clusterrolebindings.rbac.authorization.k8s.io",
                           "list storageclasses.storage.k8s.io"]:
            with self.subTest(permission=permission):
                result, calls = self.invoke(deny=permission)
                self.assertEqual(result.returncode, 1)
                self.assertIn("RBAC check failed", result.stderr)
                self.assertFalse(any(c[:1] == ["pull"] for c in calls))

    def test_namespace_scope_and_anonymous_pull(self):
        result, calls = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        create_namespace = next(c for c in calls if c[:4] == ["auth", "can-i", "create", "namespaces"])
        self.assertNotIn("--namespace", create_namespace)
        self.assertIn("--all-namespaces", create_namespace)
        self.assertTrue(any(c[:1] == ["pull"] for c in calls))

    def test_invalid_pins_and_namespace_are_rejected_before_api_calls(self):
        for kwargs in [{"version": "0x4x731"}, {"namespace": "a" * 64}]:
            result, calls = self.invoke(**kwargs)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
