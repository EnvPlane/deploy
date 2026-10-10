#!/usr/bin/env python3
"""Local mocked GitHub API checks; these do not prove hosted CI or live execution."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("component_ci", ROOT / "scripts/validate-component-ci.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
SHA = "a" * 40


def report():
    return {"schemaVersion": 1, "sourceRevision": SHA,
            "images": {name: {"repository": f"ghcr.io/envplane/{image}", "tag": f"sha-{SHA}",
                              "sourceRevision": SHA, "digest": "sha256:" + "b" * 64}
                       for name, (_, image) in gate.IMAGES.items()},
            "charts": {name: {"repository": f"oci://ghcr.io/envplane/{chart}", "version": "1.2.3",
                              "sourceRevision": SHA, "digest": "sha256:" + "b" * 64}
                       for name, chart in gate.CHARTS.items()}}


class GateTests(unittest.TestCase):
    def setUp(self):
        self.run = {"id": 20, "head_sha": SHA, "head_branch": "main", "event": "push",
                    "path": ".github/workflows/ci.yaml", "head_repository": {"full_name": "EnvPlane/runner"},
                    "status": "completed", "conclusion": "success", "run_attempt": 2}
        self.jobs = [{"name": "test", "head_sha": SHA, "run_id": 20, "run_attempt": 2,
                      "status": "completed", "conclusion": "success"}]
        self.runs = [{"id": 19}, {"id": 20}]

    def api(self, endpoint, paginate=False):
        if "workflows/ci.yaml/runs?" in endpoint:
            self.assertIn(f"head_sha={SHA}&branch=main&event=push", endpoint)
            self.assertNotIn("conclusion=success", endpoint)
            return [{"total_count": len(self.runs), "workflow_runs": self.runs}]
        if "/jobs?" in endpoint:
            self.assertIn("/runs/20/attempts/2/jobs?", endpoint)
            return [{"total_count": len(self.jobs), "jobs": self.jobs}]
        self.assertTrue(endpoint.endswith("/runs/20"))
        return copy.deepcopy(self.run)

    def verify(self):
        with patch.object(gate, "api", side_effect=self.api):
            return gate.verify("runner", SHA)

    def test_exact_success_and_latest_attempt(self):
        self.assertEqual(self.verify()["attempt"], 2)

    def test_documented_job_schema_without_attempt_field(self):
        del self.jobs[0]["run_attempt"]
        self.assertEqual(self.verify()["attempt"], 2)

    def test_missing_run(self):
        self.runs = []
        with self.assertRaisesRegex(ValueError, "missing"):
            self.verify()

    def test_all_unsuccessful_run_states(self):
        for state in [None, "failure", "cancelled", "skipped", "neutral", "timed_out", "unknown", "action_required", "stale"]:
            with self.subTest(state=state):
                self.run["conclusion"] = state
                with self.assertRaises(ValueError):
                    self.verify()
        self.run["conclusion"] = "success"
        for status in [None, "queued", "in_progress", "waiting", "unknown"]:
            with self.subTest(status=status):
                self.run["status"] = status
                with self.assertRaises(ValueError):
                    self.verify()

    def test_wrong_identity_publication_and_pull_request_refused(self):
        for key, value in [("head_sha", "c" * 40), ("head_branch", "feature"),
                           ("event", "pull_request"), ("path", ".github/workflows/publish-main.yaml"),
                           ("head_repository", {"full_name": "attacker/runner"}), ("run_attempt", None)]:
            with self.subTest(key=key):
                previous = self.run[key]
                self.run[key] = value
                with self.assertRaises(ValueError):
                    self.verify()
                self.run[key] = previous

    def test_missing_duplicate_or_skipped_required_job(self):
        original = copy.deepcopy(self.jobs)
        for jobs in [[], original * 2, [{**original[0], "name": "publish"}],
                     [{**original[0], "conclusion": "skipped"}], [{**original[0], "head_sha": "c" * 40}],
                     [{**original[0], "run_attempt": 1}], [{**original[0], "run_id": 19}],
                     [{**original[0], "status": "queued"}]]:
            with self.subTest(jobs=jobs):
                self.jobs = jobs
                with self.assertRaises(ValueError):
                    self.verify()

    def test_service_error_is_not_success(self):
        with patch.object(gate, "api", side_effect=ValueError("status unavailable")):
            with self.assertRaises(ValueError):
                gate.verify("runner", SHA)

    def test_cli_service_error_diagnostics_scrubbed(self):
        with patch.object(gate.subprocess, "run", side_effect=subprocess.CalledProcessError(
                1, ["gh"], stderr="secret token")):
            with self.assertRaisesRegex(ValueError, "service unavailable") as error:
                gate.api("repos/EnvPlane/runner/actions/runs/20")
            self.assertNotIn("secret", str(error.exception))

    def test_pagination_must_be_complete(self):
        with patch.object(gate, "api", return_value=[{"total_count": 2, "workflow_runs": [{"id": 20}]}]):
            with self.assertRaisesRegex(ValueError, "pagination"):
                gate.collection("endpoint", "workflow_runs")
        with patch.object(gate, "api", return_value=[{"total_count": 2, "workflow_runs": [{"id": 19}]},
                                                     {"total_count": 2, "workflow_runs": [{"id": 20}]}]):
            self.assertEqual(len(gate.collection("endpoint", "workflow_runs")), 2)

    def test_rerun_during_verification_refused(self):
        calls = 0

        def changing(endpoint, paginate=False):
            nonlocal calls
            result = self.api(endpoint, paginate)
            if endpoint.endswith("/runs/20"):
                calls += 1
                if calls == 2:
                    result["run_attempt"] = 3
            return result

        with patch.object(gate, "api", side_effect=changing):
            with self.assertRaisesRegex(ValueError, "changed"):
                gate.verify("runner", SHA)

    def test_new_run_during_verification_refused(self):
        calls = 0

        def changing(endpoint, paginate=False):
            nonlocal calls
            result = self.api(endpoint, paginate)
            if "workflows/ci.yaml/runs?" in endpoint:
                calls += 1
                if calls == 2:
                    result = [{"total_count": 1, "workflow_runs": [{"id": 21}]}]
            return result

        with patch.object(gate, "api", side_effect=changing):
            with self.assertRaisesRegex(ValueError, "new CI run"):
                gate.verify("runner", SHA)

    def test_report_exact_mapping(self):
        selected = gate.candidates(report())
        self.assertEqual(set(selected), {(repository, SHA) for repository, _ in gate.IMAGES.values()})

    def test_candidate_pins_closed(self):
        variants = []
        for section in ["images", "charts"]:
            candidate = report()
            candidate[section]["unknown"] = {}
            variants.append(candidate)
            candidate = report()
            del candidate[section]["runner"]
            variants.append(candidate)
        for key, value in [("sourceRevision", "main"), ("repository", "ghcr.io/attacker/runner"),
                           ("tag", "main"), ("digest", "unknown")]:
            candidate = report()
            candidate["images"]["runner"][key] = value
            variants.append(candidate)
        candidate = report()
        candidate["charts"]["runner"]["sourceRevision"] = "c" * 40
        variants.append(candidate)
        for candidate in variants:
            with self.subTest(candidate=candidate):
                with self.assertRaises(ValueError):
                    gate.candidates(candidate)
        with self.assertRaises(ValueError):
            gate.verify("unknown", SHA)

    def test_already_current_resolver_executes_gate_and_preserves_report(self):
        # Exercise real shell entrypoints with a mock gh executable, no network.
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            candidate = path / "latest-artifacts.json"
            candidate.write_text(json.dumps(report()))
            original = candidate.read_bytes()
            gh = path / "gh"
            gh.write_text("#!/bin/sh\necho mocked-status-service-error >&2\nexit 1\n")
            gh.chmod(0o755)
            env = {**os.environ, "PATH": f"{path}:{os.environ['PATH']}", "GH_TOKEN": "mock-only"}
            result = subprocess.run([str(ROOT / "scripts/resolve-compatible-manifest.sh"),
                                     "--report", str(candidate), "--main-revision", SHA],
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("CI gate refused", result.stderr)
            self.assertEqual(candidate.read_bytes(), original)

    def test_real_cli_and_current_resolver_with_mocked_success(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            candidate = path / "latest-artifacts.json"
            candidate.write_text(json.dumps(report()))
            gh = path / "gh"
            gh.write_text('''#!/usr/bin/env python3
import json, sys
endpoint = sys.argv[-1]
repo = endpoint.split('/')[2]
sha = 'a' * 40
run = dict(id=20, head_sha=sha, head_branch='main', event='push',
           path='.github/workflows/ci.yaml', head_repository=dict(full_name='EnvPlane/' + repo),
           status='completed', conclusion='success', run_attempt=2)
if 'workflows/ci.yaml/runs?' in endpoint:
    result = [dict(total_count=1, workflow_runs=[dict(id=20)])]
elif '/attempts/2/jobs?' in endpoint:
    job = dict(name='helm' if repo == 'deploy' else 'test', head_sha=sha, run_id=20,
               status='completed', conclusion='success')
    result = [dict(total_count=1, jobs=[job])]
elif endpoint.endswith('/runs/20'):
    result = run
else:
    sys.exit(1)
print(json.dumps(result))
''')
            gh.chmod(0o755)
            env = {**os.environ, "PATH": f"{path}:{os.environ['PATH']}", "GH_TOKEN": "mock-only"}
            for command in [[str(ROOT / "scripts/validate-release-gate.sh"), "--report", str(candidate)],
                            [str(ROOT / "scripts/resolve-compatible-manifest.sh"), "--report", str(candidate),
                             "--main-revision", SHA]]:
                result = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('"requiredCI"', result.stdout)

    def test_downloaded_candidate_failure_does_not_replace_input(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            original = report()
            original["sourceRevision"] = "c" * 40
            candidate = path / "original.json"
            candidate.write_text(json.dumps(original))
            original_bytes = candidate.read_bytes()
            curl = path / "curl"
            curl.write_text('''#!/usr/bin/env python3
import json, os, shutil, sys
args = sys.argv[1:]
if '-o' in args:
    shutil.copyfile(os.environ['MOCK_ARCHIVE'], args[args.index('-o') + 1])
elif '/actions/workflows/' in args[-1]:
    print(json.dumps(dict(workflow_runs=[dict(head_sha='a' * 40, id=20)])))
elif '/artifacts?' in args[-1]:
    print(json.dumps(dict(artifacts=[dict(name='envplane-compatible-artifacts', expired=False, id=30)])))
else:
    sys.exit(1)
''')
            curl.chmod(0o755)
            gh = path / "gh"
            gh.write_text("#!/bin/sh\nexit 1\n")
            gh.chmod(0o755)
            archive = path / "artifact.zip"
            env = {**os.environ, "PATH": f"{path}:{os.environ['PATH']}", "GITHUB_TOKEN": "mock-only",
                   "GH_TOKEN": "mock-only", "GITHUB_REPOSITORY": "EnvPlane/deploy", "MOCK_ARCHIVE": str(archive)}
            for selected_sha in ["b" * 40, SHA]:
                selected = report()
                selected["sourceRevision"] = selected_sha
                with zipfile.ZipFile(archive, "w") as zipped:
                    zipped.writestr("latest-artifacts.json", json.dumps(selected))
                result = subprocess.run([str(ROOT / "scripts/resolve-compatible-manifest.sh"),
                                         "--report", str(candidate), "--main-revision", SHA],
                                        env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(candidate.read_bytes(), original_bytes)
                self.assertIn("revision mismatch" if selected_sha != SHA else "CI gate refused", result.stderr)

    def test_gate_ordering_and_freshness_preservation(self):
        workflow = (ROOT / ".github/workflows/release-on-main.yaml").read_text()
        self.assertLess(workflow.index("Require exact candidate component CI"),
                        workflow.index("Select the artifact source revision"))
        self.assertLess(workflow.index("Require exact candidate component CI"),
                        workflow.index("Apply latest image pins"))
        resolver = (ROOT / "scripts/resolve-latest-published-artifacts.sh").read_text()
        self.assertLess(resolver.index('/validate-release-gate.sh"'),
                        resolver.index('previous_umbrella="$(latest_published_umbrella'))
        refresh = (ROOT / "scripts/resolve-compatible-manifest.sh").read_text()
        self.assertLess(refresh.index('--report "$manifest_file"'), refresh.index('cp "$manifest_file" "$report"'))
        self.assertLess(refresh.index('new_revision="'), refresh.index('cp "$manifest_file" "$report"'))


if __name__ == "__main__":
    unittest.main()
