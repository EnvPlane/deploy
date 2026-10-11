"""Opt-in disposable, networkless MySQL engine acceptance. No cluster changes."""
import importlib.util
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch


unit_spec = importlib.util.spec_from_file_location("prepare_unit", Path(__file__).with_name("test_prepare_mysql_source.py"))
unit = importlib.util.module_from_spec(unit_spec)
unit_spec.loader.exec_module(unit)
mod = unit.mod


@unittest.skipUnless(os.environ.get("ENVPLANE_TEST_MYSQL_PREP_DOCKER") == "1", "explicit disposable MySQL engine opt-in required")
class MySQLEngineTest(unittest.TestCase):
    def test_tls_backup_grants_and_source_data_preservation(self):
        p = unit.plan()
        name = "ep-mysql-prepare-" + secrets.token_hex(8)
        root_password = secrets.token_hex(32)
        backup_password = secrets.token_hex(32)
        app_password = secrets.token_hex(32)
        material = mod.tls_material(p)
        with tempfile.TemporaryDirectory(prefix="ep-mysql-engine-") as directory:
            os.chmod(directory, 0o700)
            base = Path(directory)
            for filename, payload in material.items():
                (base / filename).write_bytes(payload)
                os.chmod(base / filename, 0o444)
            config = base / "source.cnf"
            config.write_text("[mysqld]\nssl_ca=/etc/envplane/mysql-tls/ca.pem\nssl_cert=/etc/envplane/mysql-tls/server.pem\nssl_key=/etc/envplane/mysql-tls/server.key\ntls_version=TLSv1.2,TLSv1.3\n")
            os.chmod(config, 0o444)
            created = False
            try:
                mounts = []
                for filename in material:
                    mounts.extend(["--mount", "type=bind,source=" + str(base / filename) + ",target=/etc/envplane/mysql-tls/" + filename + ",readonly"])
                mod.run(["docker", "run", "--pull=never", "--detach", "--name", name, "--network=none", "--memory=768m", "--cpus=1",
                         "--add-host", p["tlsServerName"] + ":127.0.0.1"] + mounts + [
                         "--mount", "type=bind,source=" + str(config) + ",target=/etc/mysql/conf.d/zz-envplane-source.cnf,readonly",
                         "--env", "MYSQL_ROOT_PASSWORD=" + root_password, "--env", "MYSQL_DATABASE=" + p["database"],
                         "--env", "MYSQL_USER=customer", "--env", "MYSQL_PASSWORD=" + app_password, "mysql:8.0"])
                created = True

                def root(sql):
                    return mod.run(["docker", "exec", "-i", name] + mod.ROOT_COMMAND, sql.encode())

                deadline = time.monotonic() + 120
                while True:
                    try:
                        version = root("SELECT VERSION();\n")
                        if not version.strip().startswith(b"8.0."):
                            raise mod.Refused("Unexpected fixture engine")
                        break
                    except mod.Refused:
                        if time.monotonic() >= deadline:
                            raise mod.Refused("Disposable MySQL failed readiness") from None
                        time.sleep(1)
                root("CREATE TABLE customer_app.proof(id INT PRIMARY KEY, payload VARCHAR(32)); INSERT INTO customer_app.proof VALUES(1,'source-preserved');\n")
                before = root("SELECT id,payload FROM customer_app.proof ORDER BY id;\n")
                root(mod.sql_create(p, backup_password))
                self.assertEqual(root("SELECT ssl_type FROM mysql.user WHERE User='" + p["backupUsername"] + "';\n").strip(), b"ANY")

                class DockerClient:
                    def call(self, args, data=None):
                        command = args[args.index("--") + 1:]
                        return mod.run(["docker", "exec", "-i", name] + command, data)

                with patch.object(mod, "pod_for", return_value=name):
                    mod.verify(DockerClient(), p, backup_password)
                    wrong = dict(p, tlsServerName="wrong.source.svc")
                    # Wrong endpoint cannot be accepted as successful TLS proof.
                    with self.assertRaises(mod.Refused):
                        mod.verify(DockerClient(), wrong, backup_password)
                self.assertEqual(root("SELECT id,payload FROM customer_app.proof ORDER BY id;\n"), before)
                # Client temporary passwords are removed after successful probe.
                files = mod.run(["docker", "exec", name, "sh", "-ec", "find /tmp -maxdepth 1 -name 'ep-mysql-client.*' -print"])
                self.assertEqual(files.strip(), b"")
                # Default copy client retains only its existing app rights.
                grants = root("SHOW GRANTS FOR 'customer'@'%';\n").decode()
                self.assertNotIn("BACKUP_ADMIN", grants)
                self.assertNotIn("SHOW_ROUTINE", grants)
            finally:
                if created:
                    mod.run(["docker", "rm", "--force", "--volumes", name])


if __name__ == "__main__":
    unittest.main()
