#!/usr/bin/env python3
"""Exercise trust refusals in the no-deploy preparation check."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("prepare", ROOT / "scripts/prepare-minikube-zero-setup.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)
DIGEST = "sha256:" + "a" * 64


class PreparationTrustTests(unittest.TestCase):
    def test_release_identity_and_duplicate_component_refused(self):
        index = {"schemaVersion": 1, "channel": "stable", "version": "0.4.731",
                 "sourceRevision": "a" * 40,
                 "chart": {"repository": "oci://ghcr.io/envplane/envplane", "digest": DIGEST}}
        manifest = {"schemaVersion": 1, "sourceRevision": index["sourceRevision"],
                    "umbrella": {"name": "envplane", "version": index["version"]},
                    "images": [{"name": name, "repository": "ghcr.io/envplane/" + image,
                                "tag": "sha-" + "a" * 40, "digest": DIGEST}
                               for name, image in prepare.IMAGES.items()],
                    "childCharts": [{"name": name, "repository": "oci://ghcr.io/envplane/" + name,
                                     "version": "0.1.0", "digest": DIGEST,
                                     "sourceRevision": index["sourceRevision"]} for name in prepare.CHARTS]}
        prepare.validate(index, manifest)
        changed = copy.deepcopy(manifest)
        changed["sourceRevision"] = "b" * 40
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            prepare.validate(index, changed)
        changed = copy.deepcopy(manifest)
        changed["images"][-1] = changed["images"][0]
        with self.assertRaisesRegex(ValueError, "duplicate"):
            prepare.validate(index, changed)

    def test_mutable_version_refused(self):
        with self.assertRaisesRegex(ValueError, "invalid release identity"):
            prepare.validate({"schemaVersion": 1, "version": "latest"}, {"schemaVersion": 1})

    def test_missing_arm64_and_digest_substitution_refused(self):
        descriptor = {"digest": DIGEST, "manifests": [
            {"platform": {"os": "linux", "architecture": "amd64"}}]}
        with self.assertRaisesRegex(ValueError, "arm64/amd64"):
            prepare.platforms(descriptor, DIGEST)
        descriptor["manifests"].append({"platform": {"os": "linux", "architecture": "arm64"}})
        self.assertEqual(prepare.platforms(descriptor, DIGEST), ["linux/amd64", "linux/arm64"])
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            prepare.platforms(descriptor, "sha256:" + "b" * 64)

    def test_template_secrets_are_not_retained(self):
        rendering = "kind: Secret\ndata:\n  password: DO_NOT_RETAIN\n---\n"
        for kind, name, image in [("Deployment", "envplane-control-plane", "ghcr.io/envplane/api"),
                                  ("Deployment", "envplane-frontend", "ghcr.io/envplane/frontend"),
                                  ("StatefulSet", "envplane-control-plane-postgres", "postgres"),
                                  ("StatefulSet", "envplane-control-plane-redis", "redis")]:
            rendering += f"kind: {kind}\nmetadata:\n  name: {name}\nspec:\n  image: {image}@{DIGEST}\n---\n"
        manifest = {"images": [{"repository": "ghcr.io/envplane/" + name, "digest": DIGEST}
                               for name in ("api", "frontend")]}
        summary = prepare.rendered_summary(rendering, manifest)
        self.assertNotIn("DO_NOT_RETAIN", json.dumps(summary))
        with self.assertRaisesRegex(ValueError, "unpinned"):
            prepare.rendered_summary(rendering.replace("postgres@" + DIGEST, "postgres:latest"), manifest)
        with self.assertRaisesRegex(ValueError, "compatibility pin"):
            prepare.rendered_summary(rendering.replace("api@" + DIGEST, "api@sha256:" + "b" * 64), manifest)

    def test_failed_tools_do_not_leak_rendered_credentials(self):
        error = subprocess.CalledProcessError(1, ["helm"], output="PASSWORD", stderr="PASSWORD")
        with patch.object(prepare.subprocess, "run", side_effect=error):
            with self.assertRaisesRegex(ValueError, "chart render failed") as failure:
                prepare.run(["helm", "template"], "chart render")
        self.assertNotIn("PASSWORD", str(failure.exception))

    def test_digest_mismatch_does_not_accept_a_chart(self):
        response = subprocess.CompletedProcess(["helm"], 0, "", "Digest: sha256:" + "b" * 64)
        with patch.object(prepare.subprocess, "run", return_value=response):
            with self.assertRaisesRegex(ValueError, "frozen pin"):
                prepare.pull("helm", "oci://ghcr.io/envplane/envplane", "0.4.731", DIGEST, ROOT, {})


if __name__ == "__main__":
    unittest.main()
