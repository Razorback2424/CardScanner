#!/usr/bin/env python3
"""Reason-coded exceptions ledger shared by every game's reconciliation pass.

A ledger lists the catalog rows that are still open after a pass, one row per
(game, identity, reason). Each pass writes a fresh ledger; `diff` shows what a
batch closed and opened, and `summarize` ranks reasons so the next batch
targets the largest root cause. See docs/catalog-reconciliation-playbook.md.

Offline only: reads and writes local JSON, never contacts providers.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

LEDGER_VERSION = 1
FIELDS = ("game", "set", "identity", "reason", "detail", "evidence")
GAMES = ("pokemon", "magic", "one-piece", "lorcana", "yugioh")
REASON = re.compile(r"^[a-z][A-Za-z0-9]*$")


class LedgerError(ValueError):
    pass


def row(game: str, set_code: str, identity: str, reason: str, detail: str = "",
        evidence: dict | None = None) -> dict:
    """Build one validated ledger row."""
    entry = {"game": game, "set": set_code, "identity": identity, "reason": reason,
             "detail": detail, "evidence": dict(evidence or {})}
    validate([entry])
    return entry


def validate(rows: list[dict]) -> None:
    seen = set()
    for index, entry in enumerate(rows):
        if set(entry) != set(FIELDS):
            raise LedgerError(f"row {index}: fields must be exactly {FIELDS}")
        if entry["game"] not in GAMES:
            raise LedgerError(f"row {index}: unknown game {entry['game']!r}")
        for field in ("set", "identity", "detail"):
            if not isinstance(entry[field], str):
                raise LedgerError(f"row {index}: {field} must be a string")
        if not entry["identity"]:
            raise LedgerError(f"row {index}: identity is empty")
        if not isinstance(entry["reason"], str) or not REASON.match(entry["reason"]):
            raise LedgerError(f"row {index}: reason must be a lowerCamelCase code")
        if not isinstance(entry["evidence"], dict):
            raise LedgerError(f"row {index}: evidence must be an object")
        key = (entry["game"], entry["identity"], entry["reason"])
        if key in seen:
            raise LedgerError(f"row {index}: duplicate {key}")
        seen.add(key)


def _sorted(rows: list[dict]) -> list[dict]:
    return sorted(rows, key=lambda r: (r["game"], r["set"], r["reason"], r["identity"]))


def write_ledger(path: Path, rows: list[dict], *, source: dict | None = None) -> dict:
    """Write a deterministic ledger. `source` pins the inputs (hashes, capture builds)."""
    validate(rows)
    document = {"version": LEDGER_VERSION, "source": dict(source or {}),
                "summary": summarize(rows), "rows": _sorted(rows)}
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
    return document


def read_ledger(path: Path) -> list[dict]:
    document = json.loads(Path(path).read_text())
    if document.get("version") != LEDGER_VERSION:
        raise LedgerError(f"{path}: unsupported ledger version {document.get('version')!r}")
    rows = document.get("rows")
    if not isinstance(rows, list):
        raise LedgerError(f"{path}: rows must be a list")
    validate(rows)
    return rows


def summarize(rows: list[dict]) -> dict:
    by_reason: dict[str, Counter] = {}
    by_set: dict[str, Counter] = {}
    for entry in rows:
        by_reason.setdefault(entry["game"], Counter())[entry["reason"]] += 1
        by_set.setdefault(entry["game"], Counter())[entry["set"]] += 1
    return {
        "total": len(rows),
        "byGame": {game: sum(counter.values()) for game, counter in sorted(by_reason.items())},
        "byReason": {game: dict(counter.most_common()) for game, counter in sorted(by_reason.items())},
        "bySet": {game: dict(sorted(counter.items())) for game, counter in sorted(by_set.items())},
    }


def diff(before: list[dict], after: list[dict]) -> dict:
    """What a pass closed and opened, keyed by (game, identity, reason)."""
    key = lambda r: (r["game"], r["identity"], r["reason"])
    old = {key(r): r for r in before}
    new = {key(r): r for r in after}
    closed = _sorted([old[k] for k in old.keys() - new.keys()])
    opened = _sorted([new[k] for k in new.keys() - old.keys()])
    reasons = sorted({(r["game"], r["reason"]) for r in before + after})
    delta = {}
    for game, reason in reasons:
        was = sum(1 for r in before if r["game"] == game and r["reason"] == reason)
        now = sum(1 for r in after if r["game"] == game and r["reason"] == reason)
        if was != now:
            delta.setdefault(game, {})[reason] = {"before": was, "after": now}
    return {"before": len(before), "after": len(after), "closed": closed, "opened": opened,
            "reasonDelta": delta}


def _print_summary(summary: dict) -> None:
    print(f"{summary['total']} open rows")
    for game, reasons in summary["byReason"].items():
        print(f"  {game}: {summary['byGame'][game]}")
        for reason, count in reasons.items():
            print(f"    {count:6d}  {reason}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    show = commands.add_parser("summarize", help="Rank open rows by game and reason")
    show.add_argument("ledger", type=Path)
    compare = commands.add_parser("diff", help="Show what a pass closed and opened")
    compare.add_argument("before", type=Path)
    compare.add_argument("after", type=Path)
    compare.add_argument("--json", action="store_true", help="Print the full diff as JSON")
    args = parser.parse_args(argv)
    if args.command == "summarize":
        _print_summary(summarize(read_ledger(args.ledger)))
        return 0
    result = diff(read_ledger(args.before), read_ledger(args.after))
    if args.json:
        print(json.dumps(result, indent=1, sort_keys=True, ensure_ascii=False))
        return 0
    print(f"{result['before']} → {result['after']} open rows "
          f"({len(result['closed'])} closed, {len(result['opened'])} opened)")
    for game, reasons in result["reasonDelta"].items():
        for reason, counts in sorted(reasons.items()):
            print(f"  {game} {reason}: {counts['before']} → {counts['after']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
