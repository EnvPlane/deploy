"""Local harness checks only: these are NOT live MySQL/admission evidence."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('mysql_copy_live', Path(__file__).parents[1] / 'mysql-copy-live.py')
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)


class HarnessTests(unittest.TestCase):
    def test_go_spec_hash_html_escaping(self):
        self.assertEqual(live.metadata_hash({'a': 'x < 3 && y > 2'}),
                         '0125b84d679852d7e20fc5b882d72dd31db20b2bfa252d5d3acce638ceb9d79d')

    def test_pins_are_platform_not_floating(self):
        self.assertRegex(live.MYSQL, r'^docker.io/library/mysql@sha256:[a-f0-9]{64}$')

    def test_resources_have_correct_api(self):
        self.assertEqual(live.obj('StatefulSet', 'mysql', 'fixture')['apiVersion'], 'apps/v1')
        self.assertEqual(live.obj('Role', 'reader', 'fixture')['apiVersion'], 'rbac.authorization.k8s.io/v1')
        self.assertNotIn('namespace', live.obj('Namespace', 'fixture')['metadata'])


if __name__ == '__main__':
    unittest.main()
