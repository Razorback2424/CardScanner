#!/usr/bin/env python3
"""Catch stale -only-testing XCTest selectors before running the iOS simulator.

This checks declarations in the checked-out repository, not a historical
list of expected tests. It intentionally does not claim the tests passed.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


SELECTOR = re.compile(r"-only-testing:TradingCardScannerTests/([^\s\\]+)")
XCTEST_CLASS = re.compile(
    r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase\b"
)
TEST_METHOD = re.compile(r"\bfunc\s+(test[A-Za-z0-9_]+)\s*\(")
XCTEST_EXTENSION = re.compile(r"\bextension\s+([A-Za-z_][A-Za-z0-9_]*)\b[^\n{]*\{")
TOP_LEVEL_CLOSING_BRACE = re.compile(r"(?m)^\}\s*(?://[^\n]*)?$")


def declaration_methods(content: str, start: int) -> set[str]:
    """Read methods only within this top-level test declaration's braces.

    Swift test declarations in this repository are top-level. A method in
    another class in the same file must not validate a stale XCTest selector.
    """
    opening = content.find("{", start)
    if opening < 0:
        return set()
    closing = TOP_LEVEL_CLOSING_BRACE.search(content, opening + 1)
    if closing is None:
        return set()
    return set(TEST_METHOD.findall(content[opening + 1:closing.start()]))


def missing_selectors(workflow: Path, tests_dir: Path) -> tuple[list[str], int]:
    selections = SELECTOR.findall(workflow.read_text(encoding="utf-8"))
    if not selections:
        raise ValueError(f"No TradingCardScannerTests selectors found in {workflow}")

    declarations: dict[str, set[str]] = {}
    swift_files = sorted(tests_dir.rglob("*.swift"))
    if not swift_files:
        raise ValueError(f"No Swift test sources found under {tests_dir}")

    for source in swift_files:
        content = source.read_text(encoding="utf-8")
        for match in XCTEST_CLASS.finditer(content):
            declarations.setdefault(match.group(1), set()).update(
                declaration_methods(content, match.end())
            )
        # XCTest methods may also live in an extension of an existing test class.
        for match in XCTEST_EXTENSION.finditer(content):
            if match.group(1) in declarations:
                declarations[match.group(1)].update(
                    declaration_methods(content, match.start())
                )

    missing: list[str] = []
    for selection in selections:
        klass, separator, method = selection.partition("/")
        if klass not in declarations:
            missing.append(selection + " (class not declared)")
        elif separator and method not in declarations[klass]:
            missing.append(selection + " (method not declared in class source)")
    return missing, len(selections)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workflow", type=Path)
    parser.add_argument(
        "--tests-dir",
        type=Path,
        default=Path("TradingCardScannerTests"),
        help="Directory containing app-hosted XCTest source files",
    )
    args = parser.parse_args()
    try:
        missing, count = missing_selectors(args.workflow, args.tests_dir)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))

    if missing:
        print(f"{count} native selectors checked; {len(missing)} unresolved:")
        for selection in missing:
            print(f"  - {selection}")
        return 1

    print(f"Verified {count} native XCTest selectors against checked-out sources.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
