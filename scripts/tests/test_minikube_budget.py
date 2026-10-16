import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("budget", Path(__file__).parents[1] / "configure-minikube-budget.py")
budget = importlib.util.module_from_spec(spec)
spec.loader.exec_module(budget)


class BudgetTests(unittest.TestCase):
    def test_unlimited_container_and_wrong_target_are_refused(self):
        node = {"metadata": {"name": "envplane"}, "status": {"capacity": {"cpu": "12", "memory": "12234476Ki"}}}
        container = {"Name": "/envplane", "State": {"Running": True},
                     "HostConfig": {"NanoCpus": 4000000000, "Memory": 6442450944}}
        self.assertEqual(budget.reservation(node, container)["expectedAllocatable"],
                         {"cpuMilli": 3800, "memoryKi": 5767168})
        container["HostConfig"]["Memory"] = 0
        with self.assertRaisesRegex(ValueError, "finite"):
            budget.reservation(node, container)
        container["Name"] = "/bethunder-local"
        with self.assertRaisesRegex(ValueError, "identity"):
            budget.reservation(node, container)

    def test_existing_operator_reservation_is_preserved(self):
        with self.assertRaisesRegex(ValueError, "unmanaged"):
            budget.configured("apiVersion: x\nsystemReserved:\n  memory: 1Gi\n", {"systemReserved": {}})

    def test_canonical_units_and_oversized_allocatable(self):
        expected = {"cpuMilli": 3800, "memoryKi": 5767168}
        self.assertTrue(budget.matches_budget({"cpu": "3800m", "memory": "5632Mi"}, expected))
        self.assertTrue(budget.matches_budget({"cpu": "3800m", "memory": "5767168Ki"}, expected))
        self.assertFalse(budget.matches_budget({"cpu": "12", "memory": "12234476Ki"}, expected))
        self.assertFalse(budget.matches_budget({"cpu": "3800m", "memory": "12Gi"}, expected))

    def test_operator_content_after_managed_section_is_not_discarded(self):
        values = {"systemReserved": {"cpu": "8200m", "memory": "6467308Ki"}}
        managed = budget.configured("apiVersion: x\n", values)
        self.assertEqual(budget.configured(managed, values), managed)
        with self.assertRaisesRegex(ValueError, "section changed"):
            budget.configured(managed + "maxPods: 20\n", values)


if __name__ == "__main__":
    unittest.main()
