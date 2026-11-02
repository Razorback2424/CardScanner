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


def complete_and_successful(summary: dict) -> bool:
    return not any(summary[key] for key in ("missing", "duplicate_completions", "required_failures", "unexpected_skips"))


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
        ("focused-1", (EXACT,)), ("focused-2", (EXACT,)), ("focused-3", (EXACT,)),
        ("native-class", (NATIVE,)), ("affected-suites", AFFECTED_CLASSES),
    ]
    manifest = {
        "schema_version": 1,
        "started_utc": utc_now(),
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "toolchain": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "simulator_policy": "Existing selected simulator, reused across attempts; this recorder never erases, shuts down, or resets it.",
        "attempt_policy": "Three exact-test attempts, one full class, one affected selection; every attempt is retained regardless of success.",
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
        summary = execution_summary(log, expected_tests(selections))
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
        print(f"CENTERING_COMPARISON_END {name} {json.dumps({'exit_code': return_code, 'duration_seconds': attempt['duration_seconds'], **{key: summary[key] for key in ('counts', 'counts_source', 'completion_record_counts', 'final_suite_summary', 'count_discrepancies')}, 'execution_verified': passed, 'simulator_after': attempt['simulator_after']})}", flush=True)
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
    combined = execution_summary(args.combined_log.read_text() if args.combined_log.exists() else "", expected_tests(COMBINED_CLASSES))
    write_json(args.output / "combined-execution.json", combined)
    if not complete_and_successful(combined):
        problems.append("Combined selection failed or did not execute every relevant test method")
    print(json.dumps({"diagnostic_attempts": len(manifest["attempts"]), "combined_counts": combined["counts"],
                      **{key: combined[key] for key in ('counts_source', 'completion_record_counts', 'final_suite_summary', 'count_discrepancies')},
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
    args = parser.parse_args()
    return record(args) if args.command == "record" else verify(args)


if __name__ == "__main__":
    sys.exit(main())
