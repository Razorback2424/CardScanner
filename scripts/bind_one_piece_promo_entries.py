#!/usr/bin/env python3
"""Bind Bandai promotion-list entries to promo printings that already exist.

A promo printing added from TCGplayer records which Bandai presentation its
photo matched. A Bandai promotion entry that is still missing is bound to that
printing when exactly one printing matched its art, or when the entry's
distribution name picks exactly one of several tiers (online/offline,
participation/finalist/champion). Binding records an appearance of the
printing in its own release, evidenced by Bandai's list row. No new printing
is created.
"""

import argparse
from collections import Counter, defaultdict
from hashlib import sha256
import json
from pathlib import Path

from audit_one_piece_coverage import compare, parse_cardlist
from capture_one_piece_products import ProductCapture, atomic_json
from discover_one_piece_products import retained
from reconcile_one_piece_promo_tiers import binding_choice
from reconcile_one_piece_retail_printings import PROMO_SERIES


def bind(release, bandai):
    registry = release["registry"]
    observations = {row["id"]: row for row in release["observations"]}
    matched = defaultdict(list)
    for printing in registry["printings"]:
        if printing["status"] == "superseded":
            continue
        for item in (printing.get("review") or {}).get("evidence", []):
            alias = observations[item["observationID"]]["printedEvidence"].get("matchedBandaiArtworkAlias")
            if alias:
                matched[(printing["canonicalCardID"].split(":")[-1], alias)].append(printing)
                break
    result = {"artworks": [], "printings": [], "observations": [], "inventories": [],
              "appearances": [], "aliasAttachments": []}
    stats, ids = Counter(), []
    for series in PROMO_SERIES:
        url = "https://en.onepiece-cardgame.com/cardlist/?series=" + series
        record, raw = retained(bandai, url, "bandai-" + series + ".html")
        rows = compare([{"seriesID": series, "rows": parse_cardlist(raw, series)}], release)[0]["rows"]
        for row in rows:
            if row["status"] != "missing-printing-or-appearance" or len(row["productLabels"]) != 1:
                continue
            candidates = {p["id"]: p for p in matched.get((row["number"], row["artworkAlias"]), [])}
            if not candidates:
                stats["no-matched-printing"] += 1
                continue
            if len(candidates) == 1:
                printing = next(iter(candidates.values()))
            else:
                choice = binding_choice(row["productLabels"][0], [
                    {"qualifier": p.get("distributionLabel") or "", "tier": p.get("stamp"), "id": p["id"]}
                    for p in candidates.values()])
                if choice is None:
                    stats["tiers-not-distinguished"] += 1
                    continue
                printing = candidates[choice["id"]]
            observation_id = f"promo-entry:{series}:{row['artworkAlias']}"
            alias = {"provider": "bandai", "sourceID": f"{printing['releaseID']}:{series}:{row['artworkAlias']}"}
            result["observations"].append({
                "id": observation_id, "kind": "catalog", "language": "en", "alias": alias,
                "sourceURL": record["sourceURL"], "observedAt": record["observedAt"],
                "payloadSHA256": record["payloadSHA256"], "productEvidence": [printing["releaseID"]],
                "printedEvidence": {"number": row["number"], "sourceArtworkAlias": row["artworkAlias"],
                                    "productLabel": row["productLabels"][0], "sourceRole": "manufacturer-product-card-list"}})
            result["appearances"].append({"printingID": printing["id"], "productID": printing["releaseID"],
                                          "observationIDs": [observation_id]})
            result["aliasAttachments"].append({"printingID": printing["id"], "alias": alias})
            ids.append(observation_id)
            stats["bound"] += 1
    if ids:
        result["inventories"].append({"provider": "bandai", "paginationComplete": False, "observationIDs": sorted(ids),
                                      "snapshotID": "promo-entry-binding:" + sha256(json.dumps(sorted(ids)).encode()).hexdigest()[:16]})
    return result, stats


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--bandai-captures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Output must be a fresh path")
    result, stats = bind(json.loads(args.release.read_bytes()), ProductCapture(args.bandai_captures, offline=True))
    atomic_json(args.output, result)
    print(dict(stats))


if __name__ == "__main__":
    main()
