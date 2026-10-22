"""Offline consumer-chart checks; no cluster, credentials or issuer requests."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / "deploy/helm/envplane-control-plane"


class IssuerIntegrationChartTest(unittest.TestCase):
    def render(self, **values):
        args = ["helm", "template", "issuer-review", str(CHART),
                "--set", "frontend.enabled=false", "--set", "postgres.mode=disabled",
                "--set", "redis.mode=disabled"]
        for key, value in values.items():
            args += ["--set-string", f"{key}={value}"]
        return subprocess.run(args, capture_output=True, text=True, check=False)

    def installation(self, **overrides):
        values = {"commercialization.billing.provider": "installation",
                  "commercialization.billing.providerMode": "test",
                  "commercialization.billing.merchantAccount": "acct_fixture",
                  "commercialization.billing.baseURL": "https://billing.example.test"}
        values.update(overrides)
        return self.render(**values)

    def test_disabled_default_has_no_provider(self):
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("name: ENVPLANE_BILLING_PROVIDER\n", result.stdout)

    def test_customer_lane_has_exact_public_scope_without_seller_key(self):
        result = self.installation()
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, value in [("PROVIDER", "installation"), ("PROVIDER_MODE", "test"),
                            ("MERCHANT_ACCOUNT", "acct_fixture")]:
            self.assertEqual(result.stdout.count(f"name: ENVPLANE_BILLING_{name}\n"), 1)
            self.assertRegex(result.stdout, rf'name: ENVPLANE_BILLING_{name}\s+value: "{value}"')
        self.assertNotIn("name: ENVPLANE_BILLING_API_KEY", result.stdout)
        self.assertNotIn("name: ENVPLANE_BILLING_WEBHOOK_SECRET", result.stdout)

    def test_reject_invalid_live_or_credentialed_installation(self):
        for values in [
            {"commercialization.billing.providerMode": "live"},
            {"commercialization.billing.providerMode": "invalid"},
            {"commercialization.billing.merchantAccount": ""},
            {"commercialization.billing.apiKeySecretRef.name": "seller-key"},
            {"commercialization.billing.webhookSecretRef.name": "seller-webhook"},
            {"env.ENVPLANE_BILLING_API_KEY": "not-a-real-secret"},
        ]:
            with self.subTest(values=list(values)):
                result = self.installation(**values)
                self.assertNotEqual(result.returncode, 0)

    def test_duplicate_aliases_are_not_rendered(self):
        for key in ["env.ENVPLANE_BILLING_PROVIDER_MODE", "env.ENVPLANE_BILLING_MERCHANT_ACCOUNT",
                    "env.ENVPLANE_BILLING_PROVIDER", "env.ENVPLANE_BILLING_BASE_URL"]:
            result = self.installation(**{key: "test"})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("configure billing", result.stderr)

    def test_legacy_env_mode_is_preserved_without_duplicate(self):
        result = self.render(**{"commercialization.billing.provider": "issuer",
                                "env.ENVPLANE_BILLING_PROVIDER_MODE": "live"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(re.findall(r"name: ENVPLANE_BILLING_PROVIDER_MODE\b", result.stdout)), 1)

    def test_legacy_customer_scope_remains_supported(self):
        result = self.render(**{"commercialization.billing.provider": "installation",
                                "env.ENVPLANE_BILLING_PROVIDER_MODE": "test",
                                "env.ENVPLANE_BILLING_MERCHANT_ACCOUNT": "acct_fixture"})
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
