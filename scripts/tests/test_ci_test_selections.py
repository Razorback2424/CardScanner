"""Small, isolated tests for the CI XCTest selector audit."""

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "verify_ci_test_selections.py"
SPEC = importlib.util.spec_from_file_location("verify_ci_test_selections", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CISelectorAuditTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.tests_dir = self.root / "TradingCardScannerTests"
        self.tests_dir.mkdir()
        (self.tests_dir / "ExampleTests.swift").write_text(
            "import XCTest\n"
            "final class ExampleTests: XCTestCase {\n"
            "    func testExpectedIdentity() {}\n"
            "}\n",
            encoding="utf-8",
        )
        self.workflow = self.root / "workflow.yml"

    def audit(self, selection):
        self.workflow.write_text(
            "run: xcodebuild test \\\n"
            f"  -only-testing:TradingCardScannerTests/{selection} \\\n",
            encoding="utf-8",
        )
        return MODULE.missing_selectors(self.workflow, self.tests_dir)

    def test_existing_class_and_method(self):
        self.assertEqual(self.audit("ExampleTests/testExpectedIdentity"), ([], 1))

    def test_existing_class_selector(self):
        self.assertEqual(self.audit("ExampleTests"), ([], 1))

    def test_missing_class_is_rejected(self):
        missing, count = self.audit("TypoTests")
        self.assertEqual(count, 1)
        self.assertIn("class not declared", missing[0])

    def test_missing_method_is_rejected(self):
        missing, count = self.audit("ExampleTests/testTypo")
        self.assertEqual(count, 1)
        self.assertIn("method not declared", missing[0])

    def test_no_native_selections_is_an_error(self):
        self.workflow.write_text("name: no tests\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "No TradingCardScannerTests selectors"):
            MODULE.missing_selectors(self.workflow, self.tests_dir)


if __name__ == "__main__":
    unittest.main()
