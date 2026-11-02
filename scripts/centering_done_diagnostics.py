#!/usr/bin/env python3
"""Record a fixed native comparison plan; never retry until success or reset a simulator.

The workflow runs ``record`` before its unchanged combined selection, then ``verify``
afterwards. A failed diagnostic attempt remains a failed gate even if later attempts
pass. Logs and xcresults, not a successful build, establish test execution.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
NATIVE = "CenteringNativePrecisionTests"
EXACT = f"{NATIVE}/testTypedLocalizedDraftPreservesAllDigitsAndCommitsOnlyOnDone"
COMBINED_CLASSES = (NATIVE, "CenteringExportTests", "OpusImplementationPlanTests")
AFFECTED_CLASSES = (*COMBINED_CLASSES, "CardCenteringSurfaceTests")
SOURCES = {
    NATIVE: "TradingCardScannerTests/CenteringExportTests.swift",
    "CenteringExportTests": "TradingCardScannerTests/CenteringExportTests.swift",
    "OpusImplementationPlanTests": "TradingCardScannerTests/OpusImplementationPlanTests.swift",
    "CardCenteringSurfaceTests": "TradingCardScannerTests/UncoveredSurfaceTests.swift",
}
ALLOWED_SKIPS = {f"{NATIVE}/testNativeV2bDevelopmentPerformanceUsesUnchangedBudget"}
COMPLETION = re.compile(
    r"Test Case '-\[(?:TradingCardScannerTests\.)?(\w+) (test\w+)\]' "
    r"(passed|failed|skipped) \(([0-9.]+) seconds\)\."
)
SUITE_SUMMARY = re.compile(
    r"Test Suite '(?P<suite>Selected tests|All tests)' (?P<status>passed|failed) at [^\n]+\n"
    r"[^\n]*?\bExecuted (?P<executed>\d+) tests?, with "
    r"(?:(?P<skipped>\d+) tests? skipped and )?(?P<failure_assertions>\d+) failures? "
    r"\((?P<unexpected_assertions>\d+) unexpected\)"
)
KEYBOARD = re.compile(
    r"UIKeyboardTaskQueue|RTIInputSystemClient|remote.?keyboard|keyboard.*(?:timeout|invalid)",
    re.IGNORECASE,
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def expected_tests(selections: tuple[str, ...]) -> set[str]:
    expected: set[str] = set()
    for selection in selections:
        if "/" in selection:
            expected.add(selection)
            continue
        source = (ROOT / SOURCES[selection]).read_text()
        # The combined Debug configuration does not enable this pre-existing
        # retired slab path. These declarations are not compiled test methods.
        source = re.sub(
            r"^#if DEBUG && LEGACY_SLAB_AUTODETECTION_TESTS\n.*?^#endif\n",
            "", source, flags=re.MULTILINE | re.DOTALL,
        )
        # These XCTest classes are top-level declarations. Bound the search at
        # the next top-level class so helper/neighbor suites cannot inflate it.
        declarations = list(re.finditer(r"^(?:final )?class (\w+)\b", source, re.MULTILINE))
        declaration = next(item for item in declarations if item.group(1) == selection)
        end = next((item.start() for item in declarations if item.start() > declaration.start()), len(source))
        names = re.findall(r"\bfunc (test\w+)\s*\(", source[declaration.end():end])
        if not names:
            raise ValueError(f"No test methods discovered in {selection}")
        expected.update(f"{selection}/{name}" for name in names)
    return expected


def focused_sequencing_tests() -> tuple[str, ...]:
    native_tests = expected_tests((NATIVE,))
    required = {
        f"{NATIVE}/testPrecisionDoneUsesLatestDraftOnceAcrossRapidRefocusAndFieldChanges",
        f"{NATIVE}/testPrecisionFocusedRemovalPreservesValidInvalidAndUntouchedDraftBehavior",
    }
    missing = required - native_tests
    if missing:
        raise ValueError(f"Missing preserved sequencing regressions: {sorted(missing)}")
    # Discover the additional sequencing cases from the same source revision
    # that is built. Each explicit selection gets its own completion gate;
    # a passing aggregate cannot hide a missing or skipped new method.
    return tuple(sorted(
        required | {
            name for name in native_tests
            if name.split("/", 1)[1].startswith(("testPrecisionDone", "testPrecisionEditing"))
        }
    ))


def execution_summary(log: str, expected: set[str]) -> dict:
    completed = [
        {"test": f"{match[1]}/{match[2]}", "status": match[3], "seconds": float(match[4])}
        for match in COMPLETION.finditer(log)
    ]
    by_test: dict[str, list[dict]] = {}
    for result in completed:
        by_test.setdefault(result["test"], []).append(result)
    statuses = Counter(item["status"] for item in completed)
    record_counts = {"executed": len(completed), **{name: statuses[name] for name in ("passed", "failed", "skipped")}}
    summaries = list(SUITE_SUMMARY.finditer(log))
    suite_summary = None
    discrepancies = {}
    counts = record_counts
    counts_source = "completion_records"
    if summaries:
        final = summaries[-1]
        suite_summary = {
            "suite": final["suite"], "status": final["status"],
            **{name: int(final[name] or 0) for name in ("executed", "skipped", "failure_assertions", "unexpected_assertions")},
        }
        for name in ("executed", "skipped"):
            if suite_summary[name] != record_counts[name]:
                discrepancies[name] = {"suite_summary": suite_summary[name], "completion_records": record_counts[name]}
        # Interleaved stdout can damage individual completion lines. A final
        # zero-failure suite total still establishes aggregate passes; it never
        # supplies a missing method to the execution gates below. With failures,
        # XCTest's failure count is assertions, not necessarily failed cases.
        if suite_summary["failure_assertions"] == 0 and suite_summary["status"] == "passed" and statuses["failed"] == 0:
            counts = {"executed": suite_summary["executed"], "passed": suite_summary["executed"] - suite_summary["skipped"],
                      "failed": 0, "skipped": suite_summary["skipped"]}
            counts_source = "zero_failure_suite_summary"
    return {
        "counts": counts,
        "counts_source": counts_source,
        "completion_record_counts": record_counts,
        "final_suite_summary": suite_summary,
        "count_discrepancies": discrepancies,
        "expected_count": len(expected),
        "missing": sorted(expected - by_test.keys()),
        "duplicate_completions": sorted(name for name in expected if len(by_test.get(name, [])) > 1),
        "required_failures": sorted(name for name in expected if any(item["status"] == "failed" for item in by_test.get(name, []))),
        "unexpected_skips": sorted(name for name in expected - ALLOWED_SKIPS if any(item["status"] == "skipped" for item in by_test.get(name, []))),
        "completed": completed,
        "keyboard_diagnostic_lines": sum(bool(KEYBOARD.search(line)) for line in log.splitlines()),
    }


def xcresult_completions(payload: dict) -> list[dict]:
    """Read exact XCTest case nodes; never infer methods from suite totals."""
    if not isinstance(payload, dict):
        raise ValueError("xcresulttool output is not an object")
    roots = payload.get("testNodes")
    if not isinstance(roots, list):
        raise ValueError("xcresulttool output has no testNodes array")
    records = []

    def visit(node: dict, bundle: str | None = None) -> None:
        if not isinstance(node, dict):
            raise ValueError("Malformed xcresult test node")
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            bundle_name = node.get("name")
            if not isinstance(bundle_name, str):
                raise ValueError("Malformed xcresult test bundle name")
            bundle = bundle_name.removesuffix(".xctest")
        if node.get("nodeType") == "Test Case":
            if bundle != "TradingCardScannerTests":
                return
            identifier = node.get("nodeIdentifier", "")
            if not isinstance(identifier, str):
                raise ValueError("Malformed xcresult case identifier")
            match = re.fullmatch(r"(?:TradingCardScannerTests[./])?(\w+)/(test\w+)(?:\(\))?", identifier)
            if not match:
                raise ValueError(f"Unrecognized XCTest case identifier: {identifier!r}")
            result = node.get("result")
            if not isinstance(result, str):
                raise ValueError("Malformed xcresult case result")
            status = {"Passed": "passed", "Failed": "failed", "Skipped": "skipped"}.get(result)
            if status is None:
                raise ValueError(f"Unrecognized XCTest case result: {identifier!r}: {result!r}")
            records.append({"test": f"{match[1]}/{match[2]}", "status": status,
                            "identifier": identifier, "identifier_url": node.get("nodeIdentifierURL"),
                            "duration": node.get("duration"), "source": "xcresulttool"})
            return
        children = node.get("children", [])
        if not isinstance(children, list):
            raise ValueError("Malformed xcresult children")
        for child in children:
            visit(child, bundle)

    for node in roots:
        visit(node)
    if not records:
        raise ValueError("xcresulttool reported no exact TradingCardScannerTests cases")
    return records


def reconcile_xcresult(summary: dict, expected: set[str], bundle: Path, output: Path) -> dict:
    """Keep stdout intact and reconcile it with finalized per-method results.

    Apple documents this command in the Xcode 16.3 release notes. The testNodes /
    Test Case / nodeIdentifier contract is also used by Chromium's Xcode16LogParser.
    Unknown schema, extraction failures, disagreement and duplicate runs fail closed.
    """
    command = ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)]
    receipt = {"command": command, "bundle": str(bundle), "status": "unavailable"}
    summary["stdout_missing"] = list(summary["missing"])
    summary["status_source"] = "stdout"
    summary["result_evidence_errors"] = []
    summary["xcresult_counts"] = None
    summary["recovered_from_xcresult"] = []
    raw_path = output.with_name(output.name + "-tests.json")
    error_path = output.with_name(output.name + "-stderr.log")
    receipt_path = output.with_name(output.name + "-receipt.json")
    try:
        # Info.plist is necessary but not sufficient: successful extraction and
        # exact terminal case nodes are still required. Never inspect Staging.
        if not (bundle / "Info.plist").is_file():
            raise ValueError("No finalized result-bundle Info.plist")
        with raw_path.open("w") as stdout, error_path.open("w") as stderr:
            process = subprocess.run(command, stdout=stdout, stderr=stderr, text=True, timeout=60)
        receipt["exit_code"] = process.returncode
        receipt["raw_json"] = str(raw_path)
        receipt["stderr"] = str(error_path)
        if process.returncode != 0:
            raise ValueError(f"xcresulttool exited {process.returncode}")
        records = xcresult_completions(json.loads(raw_path.read_text()))
        receipt["status"] = "extracted"
        receipt["case_count"] = len(records)
        summary["xcresult_completed"] = records
        statuses = Counter(item["status"] for item in records)
        summary["xcresult_counts"] = {"executed": len(records),
            **{name: statuses[name] for name in ("passed", "failed", "skipped")}}
        by_bundle: dict[str, list[dict]] = {}
        by_stdout: dict[str, list[dict]] = {}
        for item in records:
            by_bundle.setdefault(item["test"], []).append(item)
        for item in summary["completed"]:
            by_stdout.setdefault(item["test"], []).append(item)
        conflicts = sorted(name for name in by_bundle.keys() & by_stdout.keys()
                           if {item["status"] for item in by_bundle[name]}
                           != {item["status"] for item in by_stdout[name]})
        if conflicts:
            summary["result_evidence_errors"].append({"status_conflicts": conflicts})
        summary["missing"] = sorted(expected - by_bundle.keys())
        summary["duplicate_completions"] = sorted(set(summary["duplicate_completions"]) |
            {name for name, items in by_bundle.items() if len(items) > 1} |
            {name for name, items in by_stdout.items() if len(items) > 1})
        summary["required_failures"] = sorted(set(summary["required_failures"]) |
            {item["test"] for item in records if item["status"] == "failed"} |
            {item["test"] for item in summary["completed"] if item["status"] == "failed"})
        summary["unexpected_skips"] = sorted(set(summary["unexpected_skips"]) |
            {item["test"] for item in records if item["test"] in expected - ALLOWED_SKIPS and item["status"] == "skipped"})
        summary["recovered_from_xcresult"] = sorted(set(summary["stdout_missing"]) - set(summary["missing"]))
        summary["status_source"] = "stdout_and_exact_xcresult_cases"
        final = summary["final_suite_summary"]
        if final and final["failure_assertions"]:
            summary["result_evidence_errors"].append("The final stdout suite reports failure assertions")
        if final and final["executed"] != len(records):
            summary["result_evidence_errors"].append("Final suite total and exact xcresult case count disagree")
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        receipt["error"] = str(error)
        summary["result_evidence_errors"].append(str(error))
    write_json(receipt_path, receipt)
    summary["xcresult_extraction"] = receipt
    return summary


def complete_and_successful(summary: dict) -> bool:
    return not any(summary.get(key) for key in ("missing", "duplicate_completions", "required_failures", "unexpected_skips", "result_evidence_errors"))


def simulator_state(device_id: str) -> dict:
    payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
    for runtime, devices in payload["devices"].items():
        for device in devices:
            if device["udid"] == device_id:
                return {"runtime": runtime, **device}
    raise ValueError(f"Selected simulator {device_id} is not available")


def record(args: argparse.Namespace) -> int:
    output: Path = args.output
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = output / "attempts.json"
    if manifest_path.exists():
        raise ValueError(f"Refusing to overwrite prior evidence: {manifest_path}")
    plan = [
        # One focused launch retains every explicit regression while leaving
        # the job budget for the complete class, affected and combined runs.
        ("focused-regressions", (EXACT, *focused_sequencing_tests())),
        ("native-class", (NATIVE,)), ("affected-suites", AFFECTED_CLASSES),
    ]
    manifest = {
        "schema_version": 1,
        "started_utc": utc_now(),
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "toolchain": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "simulator_policy": "Existing selected simulator, reused across attempts; this recorder never erases, shuts down, or resets it.",
        "attempt_policy": "One focused selection containing the localized exact test and every sequencing regression, one full class, one affected selection; every attempt is retained regardless of success.",
        "planned_attempts": [name for name, _ in plan],
        "attempts": [],
    }
    write_json(manifest_path, manifest)
    failed = False
    for name, selections in plan:
        attempt = {
            "name": name, "selections": list(selections), "started_utc": utc_now(),
            "simulator_before": simulator_state(args.device), "status": "running",
        }
        manifest["attempts"].append(attempt)
        write_json(manifest_path, manifest)
        command = [
            "xcodebuild", "test", "-project", "TradingCardScanner.xcodeproj",
            "-scheme", "TradingCardScanner", "-configuration", "Debug",
            "-destination", f"platform=iOS Simulator,id={args.device}",
            "-derivedDataPath", str(args.derived_data),
            "-resultBundlePath", str(output / f"{name}.xcresult"),
            "-parallel-testing-enabled", "NO",
            *(f"-only-testing:TradingCardScannerTests/{selection}" for selection in selections),
            "CODE_SIGNING_ALLOWED=NO",
        ]
        attempt["command"] = command
        write_json(manifest_path, manifest)
        print(f"CENTERING_COMPARISON_START {name} {attempt['started_utc']} simulator={json.dumps(attempt['simulator_before'])}", flush=True)
        started = time.monotonic()
        log_path = output / f"{name}.log"
        with log_path.open("w") as log_file:
            process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            assert process.stdout is not None
            for line in process.stdout:
                log_file.write(line)
                log_file.flush()
                print(line, end="", flush=True)
            return_code = process.wait()
        log = log_path.read_text()
        expected = expected_tests(selections)
        summary = reconcile_xcresult(execution_summary(log, expected), expected,
                                    output / f"{name}.xcresult", output / f"{name}-xcresult")
        (output / f"{name}-keyboard.log").write_text("\n".join(line for line in log.splitlines() if KEYBOARD.search(line)) + "\n")
        attempt.update({
            "status": "complete", "finished_utc": utc_now(),
            "duration_seconds": time.monotonic() - started,
            "exit_code": return_code, "simulator_after": simulator_state(args.device),
            "execution": summary,
        })
        write_json(manifest_path, manifest)
        passed = return_code == 0 and complete_and_successful(summary)
        failed |= not passed
        print(f"CENTERING_COMPARISON_END {name} {json.dumps({'exit_code': return_code, 'duration_seconds': attempt['duration_seconds'], **{key: summary[key] for key in ('counts', 'counts_source', 'completion_record_counts', 'final_suite_summary', 'count_discrepancies', 'status_source', 'xcresult_counts', 'stdout_missing', 'recovered_from_xcresult', 'missing', 'result_evidence_errors')}, 'execution_verified': passed, 'simulator_after': attempt['simulator_after']})}", flush=True)
    manifest["finished_utc"] = utc_now()
    write_json(manifest_path, manifest)
    return int(failed)


def verify(args: argparse.Namespace) -> int:
    manifest = json.loads((args.output / "attempts.json").read_text())
    problems = []
    if [attempt["name"] for attempt in manifest["attempts"]] != manifest["planned_attempts"]:
        problems.append("The fixed comparison plan did not execute completely")
    for attempt in manifest["attempts"]:
        if attempt["status"] != "complete":
            problems.append(f"{attempt['name']}: no completed result")
        elif attempt["exit_code"] != 0 or not complete_and_successful(attempt["execution"]):
            problems.append(f"{attempt['name']}: failed or missing required executed tests")
    if not args.combined_log.exists():
        problems.append("Combined selection has no retained log; no execution is established")
    expected = expected_tests(COMBINED_CLASSES)
    combined = reconcile_xcresult(
        execution_summary(args.combined_log.read_text() if args.combined_log.exists() else "", expected),
        expected, args.combined_result_bundle, args.output / "combined-xcresult")
    write_json(args.output / "combined-execution.json", combined)
    if not complete_and_successful(combined):
        problems.append("Combined selection failed or did not execute every relevant test method")
    print(json.dumps({"diagnostic_attempts": len(manifest["attempts"]), "combined_counts": combined["counts"],
                      **{key: combined[key] for key in ('counts_source', 'completion_record_counts', 'final_suite_summary', 'count_discrepancies', 'status_source', 'xcresult_counts', 'stdout_missing', 'recovered_from_xcresult', 'missing', 'result_evidence_errors')},
                      "problems": problems}, indent=2))
    return int(bool(problems))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("record")
    run.add_argument("--device", required=True)
    run.add_argument("--derived-data", required=True, type=Path)
    run.add_argument("--output", required=True, type=Path)
    check = commands.add_parser("verify")
    check.add_argument("--output", required=True, type=Path)
    check.add_argument("--combined-log", required=True, type=Path)
    check.add_argument("--combined-result-bundle", required=True, type=Path)
    args = parser.parse_args()
    return record(args) if args.command == "record" else verify(args)


if __name__ == "__main__":
    sys.exit(main())
