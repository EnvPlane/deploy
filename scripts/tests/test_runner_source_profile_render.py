import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
IMAGE = "ghcr.io/envplane/runner@sha256:" + "b" * 64
REF = dict(Namespace="base", PolicyName="envplane-pvc-copy-fence-example",
           PolicyUID="policy-uid", PolicySpecSHA256="c" * 64,
           BindingName="envplane-pvc-copy-fence-example",
           BindingUID="binding-uid", BindingSpecSHA256="d" * 64)


class RunnerSourceProfileRender(unittest.TestCase):
    def render(self, fs, sql, receipt=True):
        values = dict(image=dict(repository="ghcr.io/envplane/runner", digest="sha256:" + "b" * 64),
                      project=dict(id="arbitrary-project", clusterId="cluster"),
                      controlPlane=dict(url="https://api.example.test"),
                      pvcCopy=dict(enabled=fs, allowRootHelpers=False,
                                   sources=[dict(namespace="base", name="files", uid="files-uid")] if fs else [],
                                   fenceNames=[REF["PolicyName"]], sourceFences=[REF] if receipt else [],
                                   approvedProductionSources=[dict(Namespace="base", Name="database", UID="db-uid")]),
                      mysqlRestore=dict(enabled=sql, helperImage=IMAGE, allowRootInit=True,
                                        sourceNamespaces=["base"], targetImages=["mysql@sha256:" + "a" * 64],
                                        sourceFences=[REF] if receipt else []))
        with tempfile.TemporaryDirectory() as directory:
            fixture = pathlib.Path(directory) / "values.json"
            fixture.write_text(json.dumps(values))
            return subprocess.run(["helm", "template", "source-profile", str(ROOT / "deploy/helm/envplane-runner"),
                                   "--namespace", "runtime", "-f", str(fixture)], check=True,
                                  capture_output=True, text=True).stdout

    def test_sql_only_shared_principal_and_verified_receipts(self):
        rendered = self.render(False, True)
        self.assertEqual(rendered.count("name: ENVPLANE_PVC_COPY_RUNNER_SERVICE_ACCOUNT"), 1)
        self.assertIn("fieldPath: spec.serviceAccountName", rendered)
        self.assertIn("name: ENVPLANE_MYSQL_RESTORE_SOURCE_FENCES", rendered)
        self.assertIn("PolicySpecSHA256", rendered)
        self.assertIn("name: ENVPLANE_PVC_COPY_APPROVED_PRODUCTION_SOURCES", rendered)
        self.assertNotIn("name: ENVPLANE_PVC_COPY_HELPER_IMAGE", rendered)

    def test_mixed_shared_principal_once(self):
        rendered = self.render(True, True)
        self.assertEqual(rendered.count("name: ENVPLANE_PVC_COPY_RUNNER_SERVICE_ACCOUNT"), 1)
        self.assertIn("name: ENVPLANE_PVC_COPY_SOURCE_FENCES", rendered)
        self.assertIn("name: ENVPLANE_MYSQL_RESTORE_ALLOW_ROOT_INIT", rendered)

    def test_no_sql_capability_without_installation_receipt(self):
        rendered = self.render(False, True, receipt=False)
        self.assertNotIn("name: ENVPLANE_MYSQL_RESTORE_HELPER_IMAGE", rendered)
        self.assertNotIn("name: ENVPLANE_MYSQL_RESTORE_SOURCE_FENCES", rendered)


if __name__ == "__main__":
    unittest.main()
