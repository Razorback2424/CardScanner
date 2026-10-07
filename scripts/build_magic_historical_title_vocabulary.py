#!/usr/bin/env python3
"""Build general historical English title vocabulary, not printing authority."""
import argparse
import json
from pathlib import Path
from build_magic_historical_index import all_printings, digest

def build(all_printings_path, pilot, output):
    meta = json.loads(pilot.read_text())["meta"]
    titles = set()
    for expansion in all_printings(all_printings_path, meta):
        if expansion.get("releaseDate", "9999") >= "2014-07-18":
            continue
        for card in expansion.get("cards", []):
            if card.get("layout") not in {"normal", "split", "flip", "transform", "leveler"} or card.get("isOnlineOnly"):
                continue
            for name in [card.get("name"), card.get("faceName")]:
                if name: titles.add(name)
    artifact = {"schemaVersion": 1, "sourceSHA256": digest(all_printings_path),
                "purpose": "OCR title vocabulary only; live provider queries establish printing identities",
                "titles": sorted(titles)}
    output.write_text(json.dumps(artifact, ensure_ascii=False, separators=(",", ":")) + "\n")
    return len(titles)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all-printings", type=Path, required=True)
    parser.add_argument("--pilot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print("Historical titles:", build(args.all_printings, args.pilot, args.output))
