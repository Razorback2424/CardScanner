#!/usr/bin/env python3
"""Resolve printings held only because Bandai marks the card "Errata Card".

The errata notice changes rules text. Corrected wording appears in later
reprints, which are separate printings. A held printing is verified when the
TCGplayer group for its original release lists exactly one plain product for
that number (no treatment qualifier), and no printing already names that
product. The Super Pre-Release Edition groups are separate products and are
not counted. Anything else stays held. Output is reviewed additions for
``audit_one_piece_coverage.py --reviewed-additions``.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import re

from capture_one_piece_products import atomic_json
from one_piece_tcgcsv_capture import TCGCSVSnapshot
from reconcile_one_piece_launch_products import names_agree, normalized_name

MARKET_ROOT = "https://tcgcsv.com/tcgplayer/68/"


def release_group(label, groups):
    """The one ordinary marketplace group whose name matches the release label."""
    base = normalized_name(label.split("·")[0])
    found = [g for g in groups if "super pre-release" not in g["name"].lower()
             and (normalized_name(g["name"]) == base or normalized_name(g["name"]).endswith(base))]
    return found[0] if len(found) == 1 else None


def resolve(release, market):
    registry = release["registry"]
    observations = {row["id"]: row for row in release["observations"]}
    products = {row["id"]: row for row in registry["products"]}
    names = {row["id"]: row["name"] for row in registry["canonicalCards"]}
    groups = market.fetch_json(MARKET_ROOT + "groups")["results"]
    claimed = set()
    for printing in registry["printings"]:
        claimed |= {a["sourceID"] for a in printing["sourceAliases"] if a["provider"] == "tcgplayer"}
        claimed |= {m["productID"] for m in printing["marketMappings"] if m["provider"] == "tcgplayer"}
        for item in (printing.get("review") or {}).get("evidence", []):
            reference = observations[item["observationID"]]["printedEvidence"].get("retailerReferenceProductID")
            if reference:
                claimed.add(reference)
    result = {"artworks": [], "printings": [], "observations": [], "inventories": [], "errataResolutions": []}
    stats, held, ids = Counter(), {}, []
    for printing in registry["printings"]:
        if printing["status"] != "provisional" or not printing["supportedVariantIDs"] or not printing.get("releaseID"):
            continue
        number = printing["canonicalCardID"].split(":")[-1]
        group = release_group(products[printing["releaseID"]]["label"], groups)
        if group is None:
            held[printing["id"]] = "no-unique-release-group"; stats["held"] += 1; continue
        url = f"{MARKET_ROOT}{group['groupId']}/products"
        plain = []
        for row in market.fetch_json(url)["results"]:
            fields = {f["name"]: f["value"] for f in row.get("extendedData", [])}
            title = re.sub(r"\s*\([0-9]{3}\)\s*$", "", row["name"])
            if fields.get("Number") == number and names_agree(number, names[printing["canonicalCardID"]], title):
                plain.append(row)
        if len(plain) != 1 or str(plain[0]["productId"]) in claimed:
            held[printing["id"]] = f"{len(plain)}-plain-products-or-already-claimed"; stats["held"] += 1; continue
        product = plain[0]
        errata = "errata" in json.dumps(product.get("extendedData", [])).lower()
        source = market.manifest["captures"][url]
        observation_id = f"errata-resolution:{printing['id']}:{product['productId']}"
        result["observations"].append({
            "id": observation_id, "kind": "catalog", "language": "en",
            "alias": {"provider": "tcgplayer", "sourceID": str(product["productId"])},
            "sourceURL": url, "observedAt": source["observedAt"], "payloadSHA256": source["payloadSHA256"],
            "productEvidence": [printing["releaseID"]],
            "printedEvidence": {"sourceRole": "marketplace-single-release-product", "number": number,
                                "name": product["name"], "retailerReferenceProductID": str(product["productId"]),
                                "marketplaceErrataNote": "true" if errata else "false"}})
        ids.append(observation_id)
        result["errataResolutions"].append({
            "printingID": printing["id"], "observationID": observation_id,
            "detail": "TCGplayer lists one product for this card in its original release"
                      + (" and notes the official errata" if errata else "")
                      + "; corrected text appears only in later reprints."})
        claimed.add(str(product["productId"]))
        stats["verified"] += 1
    if ids:
        result["inventories"].append({"provider": "tcgplayer", "snapshotID": "errata-resolution:" + str(len(ids)) + ":"
                                      + market.upstream_build, "paginationComplete": False, "observationIDs": sorted(ids)})
    return result, stats, held


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--market-captures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.report.exists():
        raise ValueError("Outputs must be fresh paths")
    market = TCGCSVSnapshot(args.market_captures, "CardScannerOnePieceReview/1.0", 0.15, offline=True)
    if market.manifest.get("complete") is not True:
        raise ValueError("Errata review requires a complete retained daily TCGCSV snapshot")
    result, stats, held = resolve(json.loads(args.release.read_bytes()), market)
    atomic_json(args.output, result)
    atomic_json(args.report, {"schemaVersion": 1, "stats": dict(stats), "held": held})
    print(dict(stats))


if __name__ == "__main__":
    main()
