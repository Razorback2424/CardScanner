"""Evidence-gate regressions; these fixtures do not execute native tests."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "centering_done_diagnostics.py"
SPEC = importlib.util.spec_from_file_location("centering_done_diagnostics", SCRIPT)
diagnostics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diagnostics)


class CenteringDoneDiagnosticsTests(unittest.TestCase):
    first = "CenteringNativePrecisionTests/testPrecisionDoneFirst"
    second = "CenteringNativePrecisionTests/testPrecisionDoneSecond"

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bundle = self.root / "run.xcresult"
        self.bundle.mkdir()
        (self.bundle / "Info.plist").write_text("synthetic extraction fixture")
        self.expected = {self.first, self.second}

    @staticmethod
    def completion(identifier, status="passed"):
        suite, method = identifier.split("/")
        return f"Test Case '-[TradingCardScannerTests.{suite} {method}]' {status} (0.001 seconds).\n"

    @staticmethod
    def payload(records):
        return {"testNodes": [{"nodeType": "Test Plan", "children": [{
            "nodeType": "Unit test bundle", "name": "TradingCardScannerTests",
            "children": [{"nodeType": "Test Case", "nodeIdentifier": name + "()", "result": status}
                         for name, status in records],
        }]}]}

    def reconcile(self, log, records=None, *, raw=None, exit_code=0):
        if records is None:
            records = [(self.first, "Passed"), (self.second, "Passed")]
        encoded = json.dumps(self.payload(records)) if raw is None else raw

        def extract(command, stdout, stderr, **kwargs):
            self.assertEqual(command, ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(self.bundle)])
            stdout.write(encoded)
            stderr.write("synthetic extraction stderr\n")
            return subprocess.CompletedProcess(command, exit_code)

        with patch.object(diagnostics.subprocess, "run", side_effect=extract):
            summary = diagnostics.reconcile_xcresult(
                diagnostics.execution_summary(log, self.expected), self.expected,
                self.bundle, self.root / "run-xcresult")
        receipt = json.loads((self.root / "run-xcresult-receipt.json").read_text())
        self.assertIn("command", receipt)
        self.assertEqual((self.root / "run-xcresult-tests.json").read_text(), encoded)
        self.assertEqual(summary["xcresult_extraction"], receipt)
        return summary

    def test_recovers_only_exact_missing_method_and_retains_raw_evidence(self):
        broken = "Test Case '-[TradingCardScannerTests.Cent\nnoise\neringNativePrecisionTests testPrecisionDoneSecond]' passed (0.871 seconds).\n"
        original = self.completion(self.first) + broken
        summary = self.reconcile(original)
        self.assertTrue(diagnostics.complete_and_successful(summary))
        self.assertEqual(summary["stdout_missing"], [self.second])
        self.assertEqual(summary["recovered_from_xcresult"], [self.second])
        self.assertEqual(summary["completion_record_counts"]["executed"], 1)
        self.assertEqual(summary["xcresult_counts"]["executed"], 2)
        self.assertEqual(summary["status_source"], "stdout_and_exact_xcresult_cases")
        self.assertEqual(len(summary["completed"]), 1, "Raw stdout records must not be rewritten")

    def test_failure_from_either_source_and_status_conflict_fail(self):
        cases = [
            ("failed", "Passed"), ("passed", "Failed"), ("failed", "Failed"),
            ("skipped", "Passed"), ("passed", "Skipped"),
        ]
        for stdout_status, bundle_status in cases:
            with self.subTest(stdout=stdout_status, bundle=bundle_status):
                summary = self.reconcile(self.completion(self.first) + self.completion(self.second, stdout_status),
                                         [(self.first, "Passed"), (self.second, bundle_status)])
                self.assertFalse(diagnostics.complete_and_successful(summary))

    def test_duplicates_from_either_source_fail(self):
        log = self.completion(self.first) + self.completion(self.second)
        for duplicate_stdout in (False, True):
            with self.subTest(stdout=duplicate_stdout):
                records = [(self.first, "Passed"), (self.second, "Passed")]
                if duplicate_stdout:
                    text = log + self.completion(self.second)
                else:
                    text = log
                    records.append((self.second, "Passed"))
                summary = self.reconcile(text, records)
                self.assertFalse(diagnostics.complete_and_successful(summary))
                self.assertIn(self.second, summary["duplicate_completions"])

    def test_missing_method_cannot_be_supplied_by_aggregate_success(self):
        log = self.completion(self.first) + "Test Suite 'Selected tests' passed at now.\nExecuted 2 tests, with 0 failures (0 unexpected)\n"
        summary = self.reconcile(log, [(self.first, "Passed")])
        self.assertFalse(diagnostics.complete_and_successful(summary))
        self.assertEqual(summary["missing"], [self.second])
        self.assertTrue(summary["result_evidence_errors"])

    def test_unknown_status_invalid_json_and_empty_schema_fail_closed(self):
        log = self.completion(self.first) + self.completion(self.second)
        for raw in ("not json", "[]", "{}", json.dumps(self.payload([])),
                    json.dumps(self.payload([(self.first, "Passed"), (self.second, "Expected Failure")]))):
            with self.subTest(raw=raw):
                summary = self.reconcile(log, raw=raw)
                self.assertFalse(diagnostics.complete_and_successful(summary))
                self.assertTrue(summary["result_evidence_errors"])
                self.assertEqual(summary["recovered_from_xcresult"], [])

    def test_wrong_target_bundle_cannot_supply_identical_method_names(self):
        payload = self.payload([(self.first, "Passed"), (self.second, "Passed")])
        payload["testNodes"][0]["children"][0]["name"] = "DifferentTests"
        summary = self.reconcile("", raw=json.dumps(payload))
        self.assertFalse(diagnostics.complete_and_successful(summary))
        self.assertEqual(set(summary["missing"]), self.expected)

    def test_extraction_failure_cannot_be_overridden_by_complete_stdout(self):
        summary = self.reconcile(self.completion(self.first) + self.completion(self.second), exit_code=1)
        self.assertFalse(diagnostics.complete_and_successful(summary))
        self.assertEqual(summary["xcresult_extraction"]["exit_code"], 1)
        self.assertTrue(summary["result_evidence_errors"])

    def test_missing_bundle_fails_without_invoking_tool(self):
        with patch.object(diagnostics.subprocess, "run") as extract:
            summary = diagnostics.reconcile_xcresult(
                diagnostics.execution_summary(self.completion(self.first), {self.first}),
                {self.first}, self.root / "absent.xcresult", self.root / "absent")
        extract.assert_not_called()
        self.assertFalse(diagnostics.complete_and_successful(summary))
        self.assertTrue((self.root / "absent-receipt.json").exists())

    def test_existing_allowed_skip_remains_allowed(self):
        allowed = next(iter(diagnostics.ALLOWED_SKIPS))
        self.expected = {allowed}
        summary = self.reconcile(self.completion(allowed, "skipped"), [(allowed, "Skipped")])
        self.assertTrue(diagnostics.complete_and_successful(summary))


if __name__ == "__main__":
    unittest.main()
