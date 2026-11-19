#!/usr/bin/env python3
"""Build share metadata from Bandai captures linked to catalog printings."""
import argparse
import base64
from collections import defaultdict
import json
from pathlib import Path
from urllib.parse import parse_qs

from normalize_one_piece_sources import bandai_printed_rarities, source_url


def build_rarities(release, captures):
    rows = defaultdict(set)
    for path in captures:
        series = path.stem.removeprefix("bandai-")
        for alias, number, rarity in bandai_printed_rarities(path.read_bytes()):
            rows[series, alias, number].add(rarity)

    evidence = defaultdict(set)
    for observation in release["observations"]:
        alias = observation["alias"]
        if (alias["provider"] != "bandai" or observation["kind"] != "catalog"
                or observation["language"] != "en"):
            continue
        try:
            url = source_url("bandai", observation["sourceURL"])
        except ValueError:
            continue
        series = parse_qs(url.query).get("series", [])
        if len(series) != 1:
            continue
        printed = observation["printedEvidence"]
        artwork = printed.get("sourceArtworkAlias") or alias["sourceID"].rsplit(":", 1)[-1]
        evidence[alias["sourceID"], printed.get("number")].update(
            rows.get((series[0], artwork, printed.get("number")), ()))

    registry = release["registry"]
    numbers = {card["id"]: card["printedNumber"] for card in registry["canonicalCards"]}
    result = {}
    for printing in registry["printings"]:
        if printing["language"] != "en":
            continue
        number = numbers[printing["canonicalCardID"]]
        rarities = set().union(*(evidence.get((alias["sourceID"], number), set())
                                 for alias in printing["sourceAliases"] if alias["provider"] == "bandai"))
        if len(rarities) == 1:
            result[printing["id"].lower()] = rarities.pop()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release", type=Path, help="Bundled signed catalog envelope")
    parser.add_argument("output", type=Path)
    parser.add_argument("capture_dirs", nargs="+", type=Path, help="Directories of bandai-<series>.html captures")
    args = parser.parse_args()
    payload = json.loads(args.release.read_bytes())["payload"]
    release = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    captures = sorted({path for directory in args.capture_dirs for path in directory.glob("bandai-*.html")})
    rarities = build_rarities(release, captures)
    if not rarities:
        parser.error("no exact Bandai rarity matches found")
    args.output.write_text(json.dumps(rarities, sort_keys=True, indent=2) + "\n")
    print(f"{len(rarities)} exact One Piece rarity matches")


if __name__ == "__main__":
    main()
