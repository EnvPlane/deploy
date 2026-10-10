"""LOCAL MOCK checks. These tests never connect to Kubernetes or copy a PVC."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("pvc_copy_live", Path(__file__).resolve().parents[1] / "pvc-copy-live.py")
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


def ledger():
    run_id = "60a5a5ee57620a88"
    source, target = f"pvccopy-live-{run_id}-src", f"pvccopy-live-{run_id}-dst"
    return {"runID": run_id, "context": harness.CONTEXT, "clusterUID": "isolated", "kubeconfig": "/fixture/config",
            "sourceNamespace": source, "targetNamespace": target, "image": "ghcr.io/envplane/runner@sha256:" + "a" * 64,
            "helperBinarySHA256": "b" * 64, "storageClass": "standard", "stage": "planned",
            "namespaceUIDs": {}, "sourceUIDs": {}, "objectUIDs": {}}


class LocalMockSafetyTests(unittest.TestCase):
    def test_authorization_and_scope_refuse_without_kubernetes(self):
        for change in ({"context": "production"}, {"sourceNamespace": "test-app-base"},
                       {"targetNamespace": "default"}, {"runID": "../../test"},
                       {"image": "ghcr.io/envplane/runner:latest"}, {"helperBinarySHA256": ""}):
            data = ledger();data.update(change)
            with self.assertRaises(ValueError):
                harness.validate(data)
        with patch.object(harness.Cluster, "call") as call:
            with self.assertRaises(ValueError):
                harness.prepare(ledger(), argparse.Namespace(authorize_fixture="wrong"))
            call.assert_not_called()

    def test_both_namespace_collisions_checked_before_writes(self):
        data = ledger()
        def get(kind, name, **kwargs):
            if name == "kube-system":
                return {"metadata": {"uid": "isolated"}}
            if name == data["sourceNamespace"]:
                return None
            return {"metadata": {"uid": "foreign"}}
        with patch.object(harness.Cluster, "get", side_effect=get), patch.object(harness.Cluster, "create") as create:
            with self.assertRaisesRegex(ValueError, "already exists"):
                harness.prepare(data, argparse.Namespace(authorize_fixture=data["runID"]))
            create.assert_not_called()

    def test_fixture_initializer_contains_only_two_owned_claims_no_credentials(self):
        data = ledger();pod = harness.seed_pod(data)
        self.assertEqual(pod["metadata"]["namespace"], data["sourceNamespace"])
        self.assertEqual([v["persistentVolumeClaim"]["claimName"] for v in pod["spec"]["volumes"]], ["source", "uid-probe"])
        self.assertFalse(pod["spec"]["automountServiceAccountToken"])
        self.assertNotIn("fsGroup", pod["spec"]["securityContext"])
        raw = json.dumps(pod)
        for forbidden in ("test-app", "mysql", "secret", "hostPath", "privileged"):
            self.assertNotIn(forbidden, raw)
        self.assertIn("chown -R 1000:2000", raw)

    def test_delete_uses_exact_uid_and_resourceversion_never_labels(self):
        data = ledger();ns = data["sourceNamespace"];data["namespaceUIDs"][ns] = "ns-uid"
        cluster = harness.Cluster(data)
        obj = {"metadata": {"name": ns, "uid": "ns-uid", "resourceVersion": "7", "labels": {harness.LABEL: data["runID"]}}}
        with patch.object(cluster, "get", return_value=obj), patch.object(cluster, "call") as call:
            cluster.delete("namespace", ns)
            args, deletion = call.call_args.args
            self.assertEqual(args, ["delete", "--raw", f"/api/v1/namespaces/{ns}", "-f", "-"])
            self.assertEqual(deletion["preconditions"], {"uid": "ns-uid", "resourceVersion": "7"})
            obj["metadata"]["uid"] = "replacement"
            call.reset_mock()
            with self.assertRaises(ValueError):
                cluster.delete("namespace", ns)
            call.assert_not_called()

    def test_run_requires_review_and_matching_build_before_calls(self):
        data = ledger();data["stage"] = "prepared"
        with patch.object(harness.Cluster, "call") as call:
            with self.assertRaisesRegex(ValueError, "reviewed onboarding"):
                harness.run_cases(data, argparse.Namespace(authorize_fixture=data["runID"], reviewed_onboarding=None))
            call.assert_not_called()
        review = {**copy.deepcopy(data), "allowRootHelpers": True, "fixtureExecutionApproved": True,
                  "matchingHelperBuildVerified": True, "principal": f"system:serviceaccount:{data['targetNamespace']}:copy-runner"}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "review.json";harness.save(path, review)
            self.assertEqual(len(harness.reviewed(data, path)), 64)
            review["helperBinarySHA256"] = "c" * 64;harness.save(path, review)
            with self.assertRaises(ValueError):
                harness.reviewed(data, path)

    def test_receipt_includes_root_marker_bytes_numeric_metadata(self):
        receipt = harness.expected_receipt(ledger()["runID"])
        self.assertEqual(receipt["root"], {"uid": 1000, "gid": 2000, "mode": 0o770})
        self.assertEqual(receipt["entries"], 4)
        self.assertGreater(receipt["bytes"], 1024 * 1024)
        self.assertEqual(len(receipt["sha256"]), 64)
        self.assertNotEqual(receipt["sha256"], harness.expected_receipt("aaaaaaaaaaaaaaaa")["sha256"])

    def test_driver_only_receives_fixture_bound_identifiers(self):
        data = ledger();data["namespaceUIDs"] = {data["sourceNamespace"]: "src", data["targetNamespace"]: "dst"}
        data["sourceUIDs"] = {"source": "source-uid", "uid-probe": "probe-uid"}
        config = harness.driver_config(data, "execute")
        self.assertEqual(config["sourceUID"], "source-uid")
        self.assertEqual(config["helperBinarySHA256"], data["helperBinarySHA256"])
        with self.assertRaises(ValueError):
            harness.driver_config(data, "execute", "mysql-data")

    def test_unknown_or_active_consumers_stop_idle_gate(self):
        data = ledger();cluster = harness.Cluster(data)
        for listing in ({"items": [{"metadata": {"uid": "active"}}]}, {"items": [], "metadata": {"continue": "more"}}):
            with patch.object(cluster, "namespace"), patch.object(cluster, "call", return_value=listing):
                with self.assertRaises(ValueError):
                    cluster.idle(data["sourceNamespace"])

    def test_onboarding_has_only_fixture_sa_finite_roles_and_exact_get_cluster_reader(self):
        data = ledger()
        preview = {"sourceHelperName": "pvccopy-source-0123456789abcdef01234567", "fencePreview": [
            {"apiVersion": "admissionregistration.k8s.io/v1", "kind": "ValidatingAdmissionPolicy", "metadata": {"name": "exact-fence"}, "spec": {}},
            {"apiVersion": "admissionregistration.k8s.io/v1", "kind": "ValidatingAdmissionPolicyBinding", "metadata": {"name": "exact-fence"}, "spec": {}}]}
        manifests = harness.onboarding_manifests(data, preview)
        reader = next(obj for obj in manifests if obj["kind"] == "ClusterRole")
        self.assertTrue(all(rule["verbs"] == ["get"] and rule["resourceNames"] for rule in reader["rules"]))
        self.assertNotIn("*", json.dumps(manifests))
        self.assertNotIn("secrets", json.dumps(manifests))
        for obj in manifests:
            if "namespace" in obj["metadata"]:
                self.assertIn(obj["metadata"]["namespace"], (data["sourceNamespace"], data["targetNamespace"]))
        source_role = next(obj for obj in manifests if obj["kind"] == "Role" and obj["metadata"]["namespace"] == data["sourceNamespace"])
        pvc_rule = next(rule for rule in source_role["rules"] if rule["resources"] == ["persistentvolumeclaims"])
        self.assertEqual(pvc_rule["verbs"], ["get"])
        self.assertEqual(pvc_rule["resourceNames"], ["source", "uid-probe"])


if __name__ == "__main__":
    unittest.main()
