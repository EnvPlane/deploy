import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parents[1] / "scoped-config-snapshot.py"
SPEC = importlib.util.spec_from_file_location("snapshot", PATH)
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class SnapshotTests(unittest.TestCase):
    def obj(self, kind, spec):
        return {"apiVersion": "v1", "kind": kind, "metadata": {"name": "approved", "namespace": "scoped", "uid": "source", "resourceVersion": "10", "ownerReferences": [{"uid": "old"}], "annotations": {"kubectl.kubernetes.io/last-applied-configuration": "private", "meta.helm.sh/release-name": "owned"}}, "spec": spec, "status": {"ready": True}}

    def test_cleans_source_identity_without_dropping_helm_ownership(self):
        source = self.obj("Deployment", {"replicas": 2})
        result = m.clean(source)
        self.assertEqual(source["spec"]["replicas"], 2)
        self.assertEqual(result["spec"]["replicas"], 0)
        self.assertNotIn("uid", result["metadata"])
        self.assertNotIn("ownerReferences", result["metadata"])
        self.assertNotIn("status", result)
        self.assertNotIn("kubectl.kubernetes.io/last-applied-configuration", result["metadata"]["annotations"])
        self.assertEqual(result["metadata"]["annotations"]["meta.helm.sh/release-name"], "owned")

    def test_fresh_volume_binding_and_headless_service(self):
        result = m.clean(self.obj("PersistentVolumeClaim", {"volumeName": "source-pv", "storageClassName": "reviewed"}))
        self.assertNotIn("volumeName", result["spec"])
        self.assertEqual(result["spec"]["storageClassName"], "reviewed")
        result = m.clean(self.obj("Service", {"clusterIP": "None", "clusterIPs": ["None"], "ports": [{"port": 3306}]}))
        self.assertEqual(result["spec"]["clusterIP"], "None")
        self.assertNotIn("clusterIPs", result["spec"])
        result = m.clean(self.obj("Service", {"clusterIP": "10.1.1.1", "ports": [{"port": 80, "nodePort": 30080}]}))
        self.assertNotIn("clusterIP", result["spec"])
        self.assertNotIn("nodePort", result["spec"]["ports"][0])

    def test_flux_stays_suspended_and_sa_token_refs_not_imported(self):
        result = m.clean(self.obj("Kustomization", {"suspend": False}))
        self.assertTrue(result["spec"]["suspend"])
        source = self.obj("ServiceAccount", {})
        source["secrets"] = [{"name": "source-auto-token"}]
        self.assertNotIn("secrets", m.clean(source))


if __name__ == "__main__":
    unittest.main()
