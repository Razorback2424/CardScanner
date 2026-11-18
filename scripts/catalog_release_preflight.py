#!/usr/bin/env python3
"""Check a catalog candidate against the size limits its readers enforce.

Budgets are read from the Swift constants that verify or download each game's
catalog, so this check cannot drift from the app. A candidate fails when it is
over budget, or within --margin of it (default 5%), before anything is signed.
One Piece revision 7 was the reason: its payload passed the hosting limit but
not the 32 MiB verification cap, and that was only discovered while signing.

Offline only: reads repository sources and the candidate file.
"""
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MIB = 1024 * 1024

# (source file, constant name) per game and budget kind.
BUDGET_SOURCES = {
    "one-piece": {
        "payload": ("OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogSignature.swift", "maximumPayloadBytes"),
        "envelope": ("OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogSignature.swift", "maximumEnvelopeBytes"),
    },
    "pokemon": {
        "payload": ("PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogSnapshot.swift", "maximumPublishedBytes"),
    },
    "lorcana": {
        "payload": ("TradingCardScanner/Games/Lorcana/LorcanaCatalogRelease.swift", "maximumPayloadBytes"),
        "envelope": ("TradingCardScanner/Games/Lorcana/LorcanaCatalogRelease.swift", "maximumEnvelopeBytes"),
        "manifest": ("TradingCardScanner/Games/Lorcana/LorcanaCatalogRegistry.swift", "maximumManifestBytes"),
    },
    "yugioh": {
        "payload": ("TradingCardScanner/Games/YuGiOh/YuGiOhReleaseWire.swift", "maximumCatalogBytes"),
        "envelope": ("TradingCardScanner/Games/YuGiOh/YuGiOhReleaseWire.swift", "maximumEnvelopeBytes"),
    },
}

_FACTOR = r"\d+(?:_\d{3})*"


class PreflightError(ValueError):
    pass


def budget(game: str, kind: str, root: Path = ROOT) -> int:
    """Bytes allowed for `kind` in `game`, parsed from its Swift constant."""
    try:
        relative, name = BUDGET_SOURCES[game][kind]
    except KeyError:
        raise PreflightError(f"no {kind} budget is defined for {game}") from None
    text = (root / relative).read_text()
    match = re.search(rf"static let {name} *= *({_FACTOR}(?: *\* *{_FACTOR})*)\s*$", text, re.MULTILINE)
    if not match:
        raise PreflightError(f"{relative}: could not read {name}")
    value = 1
    for factor in match.group(1).split("*"):
        value *= int(factor.strip().replace("_", ""))
    return value


def envelope_payload_bytes(envelope: Path) -> int:
    """Decoded payload size of a signed envelope ({keyID, payload, signature})."""
    document = json.loads(envelope.read_bytes())
    encoded = document.get("payload")
    if not isinstance(encoded, str):
        raise PreflightError(f"{envelope}: no base64url payload")
    return len(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))


def check(game: str, kind: str, size: int, margin: float, root: Path = ROOT) -> dict:
    limit = budget(game, kind, root)
    used = size / limit
    if size > limit:
        status = "over"
    elif used > 1 - margin:
        status = "near"
    else:
        status = "ok"
    return {"game": game, "kind": kind, "bytes": size, "limit": limit, "headroomBytes": limit - size,
            "used": round(used, 4), "status": status}


def describe(result: dict) -> str:
    return (f"{result['game']} {result['kind']}: {result['bytes'] / MIB:.2f} MiB of "
            f"{result['limit'] / MIB:.0f} MiB ({result['used']:.1%}), "
            f"headroom {result['headroomBytes'] / MIB:.2f} MiB — {result['status']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", required=True, choices=sorted(BUDGET_SOURCES))
    parser.add_argument("--payload", type=Path, help="Unsigned canonical payload or published snapshot")
    parser.add_argument("--envelope", type=Path, help="Signed envelope; checks its size and decoded payload")
    parser.add_argument("--manifest", type=Path, help="Physical manifest (Lorcana)")
    parser.add_argument("--margin", type=float, default=0.05, help="Fail when less than this share is left")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if not (args.payload or args.envelope or args.manifest):
        parser.error("pass --payload, --envelope or --manifest")
    if not 0 <= args.margin < 1:
        parser.error("--margin must be in [0, 1)")
    results = []
    try:
        if args.payload:
            results.append(check(args.game, "payload", args.payload.stat().st_size, args.margin, args.root))
        if args.envelope:
            results.append(check(args.game, "envelope", args.envelope.stat().st_size, args.margin, args.root))
            if "payload" in BUDGET_SOURCES[args.game]:
                results.append(check(args.game, "payload", envelope_payload_bytes(args.envelope), args.margin, args.root))
        if args.manifest:
            results.append(check(args.game, "manifest", args.manifest.stat().st_size, args.margin, args.root))
    except (PreflightError, OSError, ValueError) as error:
        print(f"catalog preflight: {error}", file=sys.stderr)
        return 2
    for result in results:
        print(describe(result))
    failed = [r for r in results if r["status"] != "ok"]
    for result in failed:
        print(f"::error::{describe(result)}. Raise the limit in the reader first, or shrink the catalog.",
              file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
