"""Local harness checks only: these are NOT live MySQL/admission evidence."""
import importlib.util
from pathlib import Path
import unittest
import io
import json
import tarfile
import tempfile

spec = importlib.util.spec_from_file_location('mysql_copy_live', Path(__file__).parents[1] / 'mysql-copy-live.py')
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)
image_spec = importlib.util.spec_from_file_location('mysql_copy_live_image', Path(__file__).parents[1] / 'mysql-copy-live-image.py')
images = importlib.util.module_from_spec(image_spec)
image_spec.loader.exec_module(images)


class HarnessTests(unittest.TestCase):
    def test_secondary_cancellation_failures_never_pass(self):
        result = {'success': False, 'restoreAttempted': True, 'cancelInputBytes': 1024,
                  'errorStage': 'transfer', 'errorCode': 'cancelled', 'failureStages': ['transfer'],
                  'cleanupError': '', 'cleanupContextError': ''}
        self.assertTrue(live.clean_cancellation(result))
        for stage in ('release_ddl', 'cleanup_helpers', 'wait_source_helper_deleted'):
            self.assertFalse(live.clean_cancellation({**result, 'failureStages': ['transfer', stage]}))
        missing = dict(result); missing.pop('failureStages')
        self.assertFalse(live.clean_cancellation(missing))
        self.assertFalse(live.clean_cancellation({**result, 'cleanupContextError': 'context deadline exceeded'}))
        self.assertFalse(live.clean_cancellation({**result, 'cancelInputBytes': 0}))

    def test_go_spec_hash_html_escaping(self):
        self.assertEqual(live.metadata_hash({'a': 'x < 3 && y > 2'}),
                         '0125b84d679852d7e20fc5b882d72dd31db20b2bfa252d5d3acce638ceb9d79d')

    def test_pins_are_platform_not_floating(self):
        self.assertRegex(live.MYSQL_PARENT, r'^docker.io/library/mysql@sha256:[a-f0-9]{64}$')

    def test_resources_have_correct_api(self):
        self.assertEqual(live.obj('StatefulSet', 'mysql', 'fixture')['apiVersion'], 'apps/v1')
        self.assertEqual(live.obj('Role', 'reader', 'fixture')['apiVersion'], 'rbac.authorization.k8s.io/v1')
        self.assertNotIn('namespace', live.obj('Namespace', 'fixture')['metadata'])

    def test_archive_verifies_layers_and_fixture_labels(self):
        run_id = '77c835c7a0299753'
        layer = b'local mock layer, not a live image'
        config = json.dumps({'architecture': 'arm64', 'os': 'linux', 'rootfs': {'diff_ids': ['sha256:mock']},
            'config': {'Labels': {'envplane.io/mysql-copy-live-run': run_id, 'envplane.io/mysql-copy-parent': images.PARENT},
                       'Entrypoint': ['docker-entrypoint.sh'], 'Cmd': ['mysqld']}}).encode()
        manifest = json.dumps({'config': {'digest': images.sha(config)}, 'layers': [{'digest': images.sha(layer)}]}).encode()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mock.tar'
            with tarfile.open(path, 'w') as archive:
                for data in (config, manifest, layer):
                    entry = tarfile.TarInfo('blobs/sha256/' + images.sha(data).split(':')[1])
                    entry.size = len(data)
                    archive.addfile(entry, io.BytesIO(data))
            parent = {'layers': [{'digest': images.sha(layer)}]}
            proof = images.inspect_archive(path, images.sha(manifest), run_id, parent)
            self.assertTrue(proof['filesystemLayersUnchanged'])
            with self.assertRaisesRegex(ValueError, 'provenance labels'):
                images.inspect_archive(path, images.sha(manifest), 'ffffffffffffffff', parent)
            with self.assertRaisesRegex(ValueError, 'filesystem layer'):
                images.inspect_archive(path, images.sha(manifest), run_id, {'layers': []})

    def test_singleton_index_not_runtime_equivalence(self):
        descriptor = {'digest': 'sha256:' + 'a' * 64, 'platform': {'architecture': 'arm64', 'os': 'linux'}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mock-index.tar'
            def write_index(manifests):
                raw = json.dumps({'mediaType': 'application/vnd.oci.image.index.v1+json', 'manifests': manifests}).encode()
                with tarfile.open(path, 'w') as archive:
                    entry = tarfile.TarInfo('index.json'); entry.size = len(raw)
                    archive.addfile(entry, io.BytesIO(raw))
                return raw
            raw = write_index([descriptor])
            proof = images.index_proof(path, descriptor['digest'])
            self.assertEqual(proof['indexDigest'], images.sha(raw))
            self.assertTrue(proof['singletonIndexVerified'])
            with self.assertRaisesRegex(ValueError, 'platform/manifest'):
                images.index_proof(path, 'sha256:' + 'b' * 64)
            write_index([descriptor, descriptor])
            with self.assertRaisesRegex(ValueError, 'one descriptor'):
                images.index_proof(path, descriptor['digest'])


if __name__ == '__main__':
    unittest.main()
