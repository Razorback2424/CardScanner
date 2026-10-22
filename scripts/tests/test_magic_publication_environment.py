"""Run the publication preflight without production credentials or network access."""
import os
from pathlib import Path
import subprocess
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verify_magic_publication_environment.sh"
REQUIRED = (
    "MAGIC_CATALOG_SIGNING_KEY", "MAGIC_CATALOG_KEY_ID",
    "FIREBASE_SERVICE_ACCOUNT", "FIREBASE_PROJECT_ID", "FIREBASE_HOSTING_SITE_ID",
)


class MagicPublicationEnvironmentTests(unittest.TestCase):
    def run_preflight(self, values):
        # Never inherit a developer's real signing or hosting credentials.
        environment = {"PATH": os.defpath, "GITHUB_ENVIRONMENT": "magic-catalog-production"}
        environment.update(values)
        return subprocess.run(["bash", str(SCRIPT)], env=environment,
                              capture_output=True, text=True)

    def test_reports_every_unset_variable(self):
        result = self.run_preflight({})
        self.assertNotEqual(result.returncode, 0)
        for name in REQUIRED:
            self.assertIn(f"Missing required publication variable: {name}", result.stderr)
        self.assertIn("magic-catalog-production", result.stderr)
        self.assertIn("scope and workflow bindings", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_each_unset_or_empty_variable_blocks_publication(self):
        for name in REQUIRED:
            for empty in (False, True):
                with self.subTest(name=name, empty=empty):
                    values = dict.fromkeys(REQUIRED, "private-test-canary")
                    if empty:
                        values[name] = ""
                    else:
                        del values[name]
                    result = self.run_preflight(values)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f"Missing required publication variable: {name}", result.stderr)
                    self.assertNotIn("private-test-canary", result.stdout + result.stderr)

    def test_complete_configuration_is_silent_for_both_publication_environments(self):
        for selected in ("magic-catalog-production", "magic-catalog-production-auto"):
            with self.subTest(selected=selected):
                values = dict.fromkeys(REQUIRED, "private-test-canary")
                values["GITHUB_ENVIRONMENT"] = selected
                result = self.run_preflight(values)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout + result.stderr, "")

    def test_diagnostics_never_expand_or_execute_variable_contents(self):
        values = dict.fromkeys(REQUIRED, "$(exit 42)\nprivate-test-canary")
        values["MAGIC_CATALOG_KEY_ID"] = ""
        values["GITHUB_ENVIRONMENT"] = "private-environment-canary"
        result = self.run_preflight(values)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("private-test-canary", result.stdout + result.stderr)
        self.assertNotIn("private-environment-canary", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
