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


if __name__ == "__main__":
    unittest.main()
