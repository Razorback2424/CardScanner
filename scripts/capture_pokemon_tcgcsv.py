#!/usr/bin/env python3
"""Retain every product and price file in one daily TCGCSV Pokémon build."""
from __future__ import annotations

import argparse
from pathlib import Path

from market_price_feeds import digest, instant
from one_piece_tcgcsv_capture import BUILD_MARKER_URL, TCGCSVSnapshot, fetch_response

CATEGORY = 3
BASE = f"https://tcgcsv.com/tcgplayer/{CATEGORY}"
USER_AGENT = "ScanStash-Pokemon-CatalogAudit/1.0"
DELAY = 0.12


def is_priority(group):
    name = group["name"].casefold()
    return any(token in name for token in ("deck exclusive", "promo", "prize pack", "league & championship"))


def groups_in(snapshot):
    groups = snapshot.fetch_json(f"{BASE}/groups")["results"]
    if not groups or any(type(group.get("groupId")) is not int or group["groupId"] <= 0
                         or group.get("categoryId") != CATEGORY or not isinstance(group.get("name"), str)
                         for group in groups):
        raise ValueError("Invalid Pokémon group inventory")
    if len({group["groupId"] for group in groups}) != len(groups):
        raise ValueError("Duplicate Pokémon group IDs")
    return sorted(groups, key=lambda group: (not is_priority(group), group["groupId"]))


def capture(root: Path) -> Path:
    marker = fetch_response(BUILD_MARKER_URL, USER_AGENT, DELAY).decode().strip()
    instant(marker)
    directory = root / digest(marker.encode())[:20]
    snapshot = TCGCSVSnapshot(directory, USER_AGENT, DELAY, category_id=CATEGORY)
    if snapshot.upstream_build != marker:
        raise ValueError("TCGCSV rolled to a new daily build during startup; run again")
    if snapshot.manifest["complete"]:
        print(f"Reusing TCGCSV Pokémon build {marker}", flush=True)
        return directory
    groups = groups_in(snapshot)
    for index, group in enumerate(groups, 1):
        group_id = group["groupId"]
        for resource in ("products", "prices"):
            snapshot.fetch_json(f"{BASE}/{group_id}/{resource}")
        if index % 25 == 0 or index == len(groups):
            print(f"Captured {index}/{len(groups)} Pokémon groups", flush=True)
    snapshot.finish()
    return directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    print(capture(args.root))


if __name__ == "__main__":
    main()
