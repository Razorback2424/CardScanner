#!/usr/bin/env python3
"""Bind a cached Yu-Gi-Oh TCGCSV price capture to the provider's snapshot marker.

Reads https://tcgcsv.com/last-updated.txt, fetches every cached group's prices
again, then reads the marker once more. A group goes into the receipt only when
the marker did not move and the fresh bytes hash to the cached file, which
proves the cached prices are that snapshot. The builder consumes the result
through `--price-receipt`, so quotes carry the provider snapshot time instead
of the local capture time.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import time
import urllib.request

BASE = "https://tcgcsv.com/tcgplayer/2"
MARKER_URL = "https://tcgcsv.com/last-updated.txt"
SPACING = 0.25


def read(url, limit=64 * 1024 * 1024):
    request = urllib.request.Request(url, headers={"User-Agent": "CardScanner catalog builder"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                data = response.read(limit + 1)
            if len(data) > limit: raise ValueError(f"response exceeded size limit: {url}")
            return data
        except (OSError, ValueError):
            if attempt == 3: raise
            time.sleep(2 ** attempt)


def build_receipt(cache_dir, fetch=read, marker=None, now=None):
    marker = marker or (lambda: fetch(MARKER_URL, 1024).decode().strip())
    groups = json.loads((cache_dir / "tcgcsv/groups.json").read_bytes())["results"]
    start, rows = marker(), []
    for group in sorted(g["groupId"] for g in groups):
        cached = (cache_dir / f"tcgcsv/{group}-prices.json").read_bytes()
        url = f"{BASE}/{group}/prices"
        time.sleep(SPACING)
        fresh = fetch(url)
        digest = hashlib.sha256(cached).hexdigest()
        rows.append({"group": group, "url": url, "sha256": digest,
                     "matches_original_capture": hashlib.sha256(fresh).hexdigest() == digest,
                     "rows": len(json.loads(cached)["results"]), "bytes": len(cached)})
    end = marker()
    stable = bool(start) and start == end
    return {"snapshot_start": start, "snapshot_end": end, "snapshot_stable": stable,
            "observed_at": (now or datetime.datetime.now(datetime.timezone.utc)).isoformat(),
            "minimum_request_start_spacing_seconds": SPACING,
            "groups": [r for r in rows if stable and r["matches_original_capture"]],
            "unmatched_groups": [r["group"] for r in rows if not (stable and r["matches_original_capture"])]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache_dir", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    args = parser.parse_args()
    receipt = build_receipt(args.cache_dir)
    args.out.write_text(json.dumps(receipt, indent=1) + "\n")
    print(f"marker {receipt['snapshot_start']} -> {receipt['snapshot_end']}, stable={receipt['snapshot_stable']}, "
          f"bound {len(receipt['groups'])}, unmatched {len(receipt['unmatched_groups'])}")
    if not receipt["snapshot_stable"]: raise SystemExit("snapshot moved during the census; nothing was bound")


if __name__ == "__main__":
    main()
