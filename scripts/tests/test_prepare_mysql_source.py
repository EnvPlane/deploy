import base64
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("prepare_mysql", Path(__file__).resolve().parents[1] / "prepare-mysql-source.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def fixture():
    cluster = {"metadata": {"name": "kube-system", "uid": "cluster-uid"}}
    sts = {"kind": "StatefulSet", "metadata": {"name": "arbitrary-mysql", "namespace": "base-source", "uid": "sts-uid", "resourceVersion": "1"},
           "spec": {"replicas": 1, "template": {"metadata": {"labels": {"app": "mysql"}}, "spec": {
               "containers": [{"name": "mysql", "image": "mysql:8.4", "env": [
                   {"name": "MYSQL_DATABASE", "value": "customer_app"}, {"name": "MYSQL_USER", "value": "customer"},
                   {"name": "MYSQL_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "app-credentials", "key": "password"}}},
                   {"name": "MYSQL_ROOT_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "root-credentials", "key": "password"}}}],
                   "volumeMounts": [{"name": "db", "mountPath": "/var/lib/mysql"}]}],
               "volumes": [{"name": "db", "persistentVolumeClaim": {"claimName": "db-data"}}]}}}}
    pvc = {"metadata": {"name": "db-data", "namespace": "base-source", "uid": "pvc-uid"}, "spec": {"volumeName": "source-pv"}, "status": {"phase": "Bound"}}
    service = {"metadata": {"name": "db-service", "namespace": "base-source", "uid": "svc-uid"}, "spec": {"selector": {"app": "mysql"}, "ports": [{"port": 3306, "targetPort": "mysql"}]}}
    return cluster, sts, pvc, service


def plan():
    return mod.plan_for(*fixture(), "tenant-a", "unusual-project-id")


class ReviewTests(unittest.TestCase):
    def test_preview_is_deterministic_metadata_only(self):
        p = plan()
        self.assertEqual(p, plan())
        self.assertEqual(p["tlsServerName"], "db-service.base-source.svc")
        self.assertEqual(p["database"], "customer_app")
        self.assertNotIn("data", p)
        self.assertNotIn("template", p)
        self.assertEqual(len(p["backupUsername"]), 30)
        self.assertNotEqual(p["backupUsername"], "customer")

    def test_identity_or_tenant_change_invalidates_review(self):
        original = plan()
        cluster, sts, pvc, svc = fixture()
        for obj in (cluster, sts, pvc, svc):
            previous = obj["metadata"]["uid"]
            obj["metadata"]["uid"] += "-replaced"
            self.assertNotEqual(mod.plan_for(cluster, sts, pvc, svc, "tenant-a", "unusual-project-id")["digest"], original["digest"])
            obj["metadata"]["uid"] = previous
        self.assertNotEqual(mod.plan_for(*fixture(), "tenant-b", "unusual-project-id")["digest"], original["digest"])

    def test_unsafe_layouts_refused(self):
        mutations = [
            lambda s: s["spec"].update(replicas=2),
            lambda s: s["spec"].update(updateStrategy={"type": "OnDelete"}),
            lambda s: s["spec"].update(updateStrategy={"type": "RollingUpdate", "rollingUpdate": {"partition": 1}}),
            lambda s: s["spec"]["template"]["spec"]["containers"][0].update(image="mysql:latest"),
            lambda s: s["spec"]["template"]["spec"]["containers"][0].update(image="malicious.test/mysql:8.4"),
            lambda s: s["spec"]["template"]["spec"]["containers"][0].update(args=["--skip-grant-tables"]),
            lambda s: s["spec"]["template"]["spec"]["containers"][0].update(envFrom=[{}]),
            lambda s: s["spec"]["template"]["spec"]["containers"].append({"name": "sidecar"}),
            lambda s: s["spec"]["template"]["spec"]["containers"][0]["volumeMounts"].append({"name": "config", "mountPath": "/etc/mysql/conf.d"}),
            lambda s: s["spec"]["template"]["spec"]["containers"][0]["env"][0].update(value="app`; DROP DATABASE app; --"),
            lambda s: s["spec"]["template"]["spec"]["containers"][0]["env"][3].update(valueFrom={"secretKeyRef": {"name": "root-credentials", "key": "password", "optional": True}}),
        ]
        for mutate in mutations:
            cluster, sts, pvc, svc = fixture()
            mutate(sts)
            with self.subTest(sts=sts), self.assertRaises(mod.Refused):
                mod.plan_for(cluster, sts, pvc, svc, "tenant-a", "project")

    def test_application_and_pvc_configuration_unchanged(self):
        _, sts, _, _ = fixture()
        original = copy.deepcopy(sts["spec"]["template"])
        changed = mod.prepared_template(plan(), original)
        self.assertEqual(sts["spec"]["template"], original)
        self.assertEqual(changed["spec"]["containers"][0]["env"], original["spec"]["containers"][0]["env"])
        self.assertEqual(changed["spec"]["volumes"][0], original["spec"]["volumes"][0])
        self.assertNotIn("args", changed["spec"]["containers"][0])
        self.assertTrue(all(m["readOnly"] for m in changed["spec"]["containers"][0]["volumeMounts"][1:]))

    def test_sql_has_only_dedicated_schema_catalog_and_backup_grants(self):
        sql = mod.sql_create(plan(), "a" * 64)
        self.assertIn("REQUIRE SSL", sql)
        self.assertIn("ON `customer_app`.*", sql)
        self.assertIn("SHOW_ROUTINE, BACKUP_ADMIN ON *.*", sql)
        for forbidden in ("ALL PRIVILEGES", "GRANT OPTION", "ALTER USER", "DROP", "INSERT", "UPDATE", "DELETE", "FLUSH", "RELOAD"):
            self.assertNotIn(forbidden, sql)
        with self.assertRaises(mod.Refused):
            mod.sql_create(plan(), "quote'escape")

    def test_grant_proof_rejects_wrong_schema_global_read_and_roles(self):
        p = plan()
        account = "`" + p["backupUsername"] + "`@`%`"
        good = ["GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON `customer_app`.* TO " + account, "GRANT BACKUP_ADMIN, SHOW_ROUTINE ON *.* TO " + account]
        mod.validate_grants(p, good)
        for bad in ([good[0].replace("customer_app", "another_app"), good[1]], good + ["GRANT SELECT ON *.* TO " + account], good + ["GRANT `role`@`%` TO " + account], [good[0] + " WITH GRANT OPTION", good[1]], good + ["GRANT BACKUP_ADMIN ON *.* TO 'other'@'%'"]):
            with self.subTest(grants=bad), self.assertRaises(mod.Refused):
                mod.validate_grants(p, bad)

    def test_secret_ownership_and_immutable_required(self):
        p = plan()
        secret = mod.owned_secret(p, p["credentialSecret"], {"password": b"fixture"})
        secret["metadata"]["uid"] = "secret-uid"
        mod.check_owned(p, secret)
        for mutate in (lambda x: x.update(immutable=False), lambda x: x["metadata"]["annotations"].update({"envplane.io/source-uid": "other"}), lambda x: x["metadata"].update(deletionTimestamp="now")):
            other = copy.deepcopy(secret)
            mutate(other)
            with self.assertRaises(mod.Refused):
                mod.check_owned(p, other)

    def test_approval_rejected_before_any_kubernetes_call(self):
        class NoAccess:
            def get(self, *_):
                raise AssertionError("Unapproved Kubernetes call")
        p = plan()
        for approval, restart in (("wrong", True), (p["digest"], False)):
            with self.assertRaises(mod.Refused):
                mod.apply(NoAccess(), p, approval, restart)
        p["database"] = "another"
        with self.assertRaises(mod.Refused):
            mod.apply(NoAccess(), p, p["digest"], True)

    def test_tls_material_has_verified_service_san_and_no_ca_private_key(self):
        material = mod.tls_material(plan())
        self.assertEqual(set(material), {"ca.pem", "server.pem", "server.key"})
        self.assertTrue(material["server.key"].startswith(b"-----BEGIN PRIVATE KEY-----"))

    def test_exec_verification_keeps_credentials_off_argv_and_cleans_tmpfile(self):
        captured = []
        class Fake:
            def call(self, args, data=None):
                captured.append((args, data))
                user = plan()["backupUsername"]
                return ("Ssl_cipher\tTLS_AES_256_GCM_SHA384\nGRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON `customer_app`.* TO `" + user + "`@`%`\nGRANT SHOW_ROUTINE, BACKUP_ADMIN ON *.* TO `" + user + "`@`%`\n").encode()
        with patch.object(mod, "pod_for", return_value="source-0"):
            mod.verify(Fake(), plan(), "a" * 64)
        args, stdin = captured[0]
        self.assertNotIn("a" * 64, " ".join(args))
        self.assertIn(b"a" * 64, stdin)
        self.assertIn("VERIFY_IDENTITY", " ".join(args))
        self.assertNotIn("exec mysql", " ".join(args))
        self.assertIn("trap", " ".join(args))


class ApplyTests(unittest.TestCase):
    def fake(self):
        cluster, sts, pvc, svc = fixture()
        p = mod.plan_for(cluster, sts, pvc, svc, "tenant-a", "unusual-project-id")

        class FakeKubernetes:
            namespace = p["namespace"]
            prefix = ["fixture-kubectl"]
            def __init__(self):
                self.objects = {("statefulset", p["statefulSet"]): sts, ("pvc", p["pvc"]): pvc, ("service", p["service"]): svc}
                self.secrets = {}
                self.created = []
                self.account = False
                self.failure = False

            def get(self, kind, name):
                return copy.deepcopy(self.objects[kind, name])

            def optional_secret(self, name):
                return copy.deepcopy(self.secrets.get(name))

            def create(self, obj):
                self.created.append(obj["metadata"]["name"])
                obj = copy.deepcopy(obj)
                obj["metadata"]["uid"] = "owned-" + obj["metadata"]["name"]
                self.secrets[obj["metadata"]["name"]] = obj
                return obj

            def call(self, args, data=None, timeout=45):
                if args[0] == "patch":
                    if self.failure:
                        raise mod.Refused("Fixture patch rejected")
                    ops = __import__("json").loads(data)
                    self.objects["statefulset", p["statefulSet"]]["spec"]["template"] = ops[-1]["value"]
                    return b"{}"
                if args[0] == "rollout":
                    return b""
                raise AssertionError("Unexpected fixture operation")

        fake = FakeKubernetes()

        def root_sql(_, __, sql):
            if sql == "SELECT VERSION();\n":
                return b"8.4.6\n"
            if "SELECT COUNT(*)" in sql:
                return b"1\n" if fake.account else b"0\n"
            if "SELECT ssl_type" in sql:
                return b"ANY\n"
            if sql.startswith("CREATE USER"):
                fake.account = True
                return b""
            raise AssertionError("Unexpected fixture SQL")
        return p, fake, cluster, root_sql

    def test_apply_and_retry_reuse_credentials_without_account_rotation(self):
        p, fake, cluster, root = self.fake()
        import json
        with patch.object(mod, "run", return_value=json.dumps(cluster).encode()), patch.object(mod, "root_sql", side_effect=root) as sql, patch.object(mod, "tls_material", return_value={"ca.pem": b"public-ca", "server.pem": b"cert", "server.key": b"key"}), patch.object(mod, "verify") as verify:
            result = mod.apply(fake, p, p["digest"], True)
            self.assertEqual(result["status"], "verified")
            self.assertTrue(result["sourceRestarted"])
            private_before = copy.deepcopy(fake.secrets)
            retry = mod.apply(fake, p, p["digest"], True)
            self.assertFalse(retry["sourceRestarted"])
            self.assertTrue(fake.secrets == private_before, "Retry changed protected credentials")
            self.assertEqual(len(fake.created), 3)
            self.assertEqual(sum(c.args[2].startswith("CREATE USER") for c in sql.call_args_list), 1)
            self.assertEqual(verify.call_count, 2)

    def test_partial_patch_failure_retains_owned_secrets_and_can_retry(self):
        p, fake, cluster, root = self.fake()
        import json
        with patch.object(mod, "run", return_value=json.dumps(cluster).encode()), patch.object(mod, "root_sql", side_effect=root), patch.object(mod, "tls_material", return_value={"ca.pem": b"public-ca", "server.pem": b"cert", "server.key": b"key"}), patch.object(mod, "verify"):
            fake.failure = True
            with self.assertRaises(mod.Refused):
                mod.apply(fake, p, p["digest"], True)
            self.assertEqual(len(fake.secrets), 3)
            self.assertFalse(fake.account)
            fake.failure = False
            self.assertEqual(mod.apply(fake, p, p["digest"], True)["status"], "verified")
            self.assertEqual(len(fake.created), 3)

    def test_existing_account_without_owned_credentials_is_not_adopted(self):
        p, fake, cluster, root = self.fake()
        import json
        fake.account = True
        with patch.object(mod, "run", return_value=json.dumps(cluster).encode()), patch.object(mod, "root_sql", side_effect=root):
            with self.assertRaises(mod.Refused):
                mod.apply(fake, p, p["digest"], True)
        self.assertEqual(fake.created, [])

    def test_source_uid_drift_refused_before_sql_and_writes(self):
        p, fake, cluster, _ = self.fake()
        import json
        fake.objects["pvc", p["pvc"]]["metadata"]["uid"] = "replaced"
        with patch.object(mod, "run", return_value=json.dumps(cluster).encode()), patch.object(mod, "root_sql") as sql:
            with self.assertRaises(mod.Refused):
                mod.apply(fake, p, p["digest"], True)
            sql.assert_not_called()
        self.assertEqual(fake.created, [])


if __name__ == "__main__":
    unittest.main()
