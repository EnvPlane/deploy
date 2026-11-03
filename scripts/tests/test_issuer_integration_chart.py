"""Offline consumer-chart checks; no cluster, credentials or issuer requests."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / "deploy/helm/envplane-control-plane"


class IssuerIntegrationChartTest(unittest.TestCase):
    def render(self, chart=CHART, **values):
        args = ["helm", "template", "issuer-review", str(chart),
                "--set", "frontend.enabled=false", "--set", "postgres.mode=disabled",
                "--set", "redis.mode=disabled"]
        for key, value in values.items():
            option = "--set" if key.endswith("issuerConnection.enabled") else "--set-string"
            args += [option, f"{key}={value}"]
        return subprocess.run(args, capture_output=True, text=True, check=False)

    def installation(self, **overrides):
        values = {"commercialization.billing.provider": "installation",
                  "commercialization.billing.providerMode": "test",
                  "commercialization.billing.merchantAccount": "acct_fixture",
                  "commercialization.billing.baseURL": "https://billing.example.test"}
        values.update(overrides)
        return self.render(**values)

    def connection(self, **overrides):
        prefix = "commercialization.issuerConnection"
        values = {f"{prefix}.enabled": "true",
                  f"{prefix}.profile": "sandbox",
                  f"{prefix}.profiles.sandbox.baseURL": "https://billing.example.test",
                  f"{prefix}.profiles.sandbox.merchantAccount": "acct_sandbox_fixture",
                  f"{prefix}.profiles.sandbox.activationIssuerURL": "https://metadata.example.test",
                  # Render fixture only, not an accepted cryptographic trust root.
                  f"{prefix}.profiles.sandbox.activationPublicKeysJSON": '[{"kid":"fixture"}]'}
        values.update(overrides)
        return self.render(**values)

    def test_sandbox_profile_renders_one_complete_public_connection(self):
        result = self.connection()
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, value in {
            "BILLING_PROVIDER": "installation", "BILLING_PROVIDER_MODE": "test",
            "BILLING_MERCHANT_ACCOUNT": "acct_sandbox_fixture",
            "BILLING_BASE_URL": "https://billing.example.test",
            "ACTIVATION_ISSUER_URL": "https://metadata.example.test",
        }.items():
            self.assertEqual(result.stdout.count(f"name: ENVPLANE_{name}\n"), 1)
            self.assertRegex(result.stdout, rf'name: ENVPLANE_{name}\s+value: "{re.escape(value)}"')
        self.assertNotIn("name: ENVPLANE_BILLING_API_KEY", result.stdout)
        self.assertNotIn("name: ENVPLANE_BILLING_WEBHOOK_SECRET", result.stdout)

    def test_profile_requires_complete_unambiguous_public_handoff(self):
        prefix = "commercialization.issuerConnection.profiles.sandbox"
        cases = [
            {f"{prefix}.baseURL": ""}, {f"{prefix}.merchantAccount": ""},
            {f"{prefix}.activationIssuerURL": ""},
            {f"{prefix}.activationPublicKeysJSON": "[]"},
            {f"{prefix}.activationPublicKeysJSON": "{}"},
            {f"{prefix}.activationPublicKeysJSON": "broken"},
            {"commercialization.billing.provider": "issuer"},
            {"commercialization.billing.apiKeySecretRef.name": "seller-key"},
            {"commercialization.license.activationIssuerURL": "https://other.example.test"},
            {"env.ENVPLANE_ACTIVATION_PUBLIC_KEYS_JSON": "[]"},
            {"env.ENVPLANE_BILLING_BASE_URL": "https://other.example.test"},
        ]
        for url in ["http://billing.example.test", "https://user@billing.example.test",
                    "https://billing.example.test/path", "https://billing.example.test?q=1"]:
            cases.append({f"{prefix}.baseURL": url})
        for values in cases:
            with self.subTest(values=values):
                result = self.connection(**values)
                self.assertNotEqual(result.returncode, 0)

    def test_production_is_explicit_and_never_falls_back_to_sandbox(self):
        result = self.connection(**{"commercialization.issuerConnection.profile": "production"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LIVE-compatible", result.stderr)
        result = self.connection(**{"commercialization.issuerConnection.profile": "typo"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sandbox or production", result.stderr)

    def test_disabled_profile_does_not_enable_billing(self):
        result = self.connection(**{"commercialization.issuerConnection.enabled": "false"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("name: ENVPLANE_BILLING_PROVIDER\n", result.stdout)
        self.assertNotIn("acct_sandbox_fixture", result.stdout)

    def test_vendored_umbrella_has_sandbox_selector_and_live_gate(self):
        prefix = "envplane-control-plane.commercialization.issuerConnection"
        result = self.render(chart=ROOT / "deploy/helm/envplane")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("name: ENVPLANE_BILLING_PROVIDER\n", result.stdout)
        result = self.render(chart=ROOT / "deploy/helm/envplane", **{
            f"{prefix}.enabled": "true", f"{prefix}.profile": "production"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("LIVE-compatible", result.stderr)

    def test_disabled_default_has_no_provider(self):
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("name: ENVPLANE_BILLING_PROVIDER\n", result.stdout)

    def test_default_production_cannot_silently_select_sandbox(self):
        for chart, prefix in [(CHART, "commercialization.issuerConnection"),
                              (ROOT / "deploy/helm/envplane", "envplane-control-plane.commercialization.issuerConnection")]:
            with self.subTest(chart=chart):
                result = self.render(chart=chart, **{f"{prefix}.enabled": "true"})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("LIVE-compatible", result.stderr)
                values = (chart / "values.yaml").read_text()
                self.assertRegex(values, r"issuerConnection:\s+enabled: false\s+profile: production")

    def test_shipped_sandbox_requires_authenticated_roots(self):
        result = self.render(**{"commercialization.issuerConnection.enabled": "true",
                                "commercialization.issuerConnection.profile": "sandbox"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("authenticated activationPublicKeysJSON", result.stderr)

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
