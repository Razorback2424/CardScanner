#!/usr/bin/env python3
"""Record a product's reprint as an appearance of the original printing.

Bandai lists some reprints under the product that reissued them, with an
``_r`` presentation: starter decks and the PRB-01 premium booster. Where
TCGplayer files that reprint as its own product, the retail replay adds a
separate printing. Where TCGplayer lists no separate product for the number
in that product's group, collectors trade it as the original card, so the
original printing gains an appearance in the reprinting product. No new
ownership identity is created.

An appearance is recorded only when all of the following hold:

* The ``_r`` row is still missing from the catalog, and its series belongs
  to a product in the reviewed product manifest.
* The product's marketplace group has no unclaimed product with that number.
* Exactly one verified printing of the number, without a treatment, stamp or
  distribution, has official art that matches the ``_r`` render within
  ``REPRINT_RENDER_LIMIT`` across the three comparison regions. Reprint renders
  move the watermark and change the footer, so they miss the strict limit.
"""

import argparse
from collections import Counter
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import re
from urllib.error import HTTPError

from audit_one_piece_coverage import compare, parse_cardlist
from capture_one_piece_products import ProductCapture, atomic_json
from discover_one_piece_products import retained
from one_piece_tcgcsv_capture import TCGCSVSnapshot
from reconcile_one_piece_retail_printings import ARTWORK_REGIONS, COMPARISON_SIZE, MARKET_ROOT

REPRINT_RENDER_LIMIT = 0.06


def resolve(release, products, bandai, artwork, market):
    from PIL import Image, ImageChops, ImageStat

    registry = release["registry"]
    observations = {row["id"]: row for row in release["observations"]}
    artworks = {row["id"]: row for row in registry["artworks"]}

    def image(url, filename):
        try:
            _, raw = artwork.capture(url, filename)
        except (HTTPError, ValueError):
            return None
        with Image.open(BytesIO(raw)) as picture:
            return picture.convert("RGB").resize(COMPARISON_SIZE, Image.Resampling.BILINEAR)

    def render_url(printing):
        art = artworks[printing["artworkID"]]
        for oid in sorted(art["observationIDs"]):
            row = observations.get(oid)
            if (row and row["alias"]["provider"] == "bandai" and row.get("imageSHA256") == art.get("imageSHA256")
                    and row["sourceURL"].startswith("https://en.onepiece-cardgame.com/images/")):
                return row["sourceURL"]
        return None

    claimed = set()
    for printing in registry["printings"]:
        claimed |= {a["sourceID"] for a in printing["sourceAliases"] if a["provider"] == "tcgplayer"}
        claimed |= {m["productID"] for m in printing["marketMappings"] if m["provider"] == "tcgplayer"}
        for item in (printing.get("review") or {}).get("evidence", []):
            reference = observations[item["observationID"]]["printedEvidence"].get("retailerReferenceProductID")
            if reference:
                claimed.add(reference)
    originals = {}
    for printing in registry["printings"]:
        if (printing["status"] == "verified" and printing.get("treatment") in (None, "Standard artwork")
                and not printing.get("stamp") and not printing.get("distributionLabel")):
            originals.setdefault(printing["canonicalCardID"], []).append(printing)

    result = {"artworks": [], "printings": [], "observations": [], "inventories": [],
              "appearances": [], "aliasAttachments": []}
    stats, held, ids = Counter(), {}, []
    for product in products["products"]:
        list_url = product["manufacturerListURL"]
        series = re.search(r"series=([0-9]+)", list_url)[1]
        record, raw = retained(bandai, list_url, "bandai-" + series + ".html")
        text = raw.decode("utf-8")
        rows = compare([{"seriesID": series, "rows": parse_cardlist(raw, series)}], release)[0]["rows"]
        market_numbers = {}
        for row in market.fetch_json(MARKET_ROOT + product["retailerGroupID"] + "/products")["results"]:
            number = [f["value"] for f in row.get("extendedData", []) if f["name"] == "Number"]
            if number and str(row["productId"]) not in claimed:
                market_numbers.setdefault(number[0], []).append(row["productId"])
        for row in rows:
            alias, number = row["artworkAlias"], row["number"]
            if row["status"] != "missing-printing-or-appearance" or not re.fullmatch(re.escape(number or "") + r"_r[0-9]+", alias):
                continue
            key = f"{series}/{alias}"
            if number in market_numbers:
                held[key] = "marketplace-lists-a-separate-product"; stats["held"] += 1; continue
            match = re.search(r'data-src="\.\./images/cardlist/card/' + re.escape(alias) + r'\.png\?([0-9]+)"', text)
            reprint = image(f"https://en.onepiece-cardgame.com/images/cardlist/card/{alias}.png?{match[1]}",
                            f"bandai/{series}-{alias}.png") if match else None
            if reprint is None:
                held[key] = "official-reprint-render-missing"; stats["held"] += 1; continue
            matches = []
            for printing in originals.get("one-piece:en:" + number, []):
                url = render_url(printing)
                original = image(url, "bandai/original-" + artworks[printing["artworkID"]]["imageSHA256"] + ".png") if url else None
                if original is None:
                    continue
                diff = ImageChops.difference(reprint, original)
                # Reprint renders move Bandai's SAMPLE watermark and change the footer (EN marker,
                # block icon), so the same art lands just past the strict limit.
                if max(sum(ImageStat.Stat(diff.crop(r)).mean) / (3 * 255) for r in ARTWORK_REGIONS) <= REPRINT_RENDER_LIMIT:
                    matches.append(printing)
            if len(matches) != 1:
                held[key] = f"{len(matches)}-matching-original-printings"; stats["held"] += 1; continue
            original = matches[0]
            if any(a["printingID"].lower() == original["id"].lower() and a["productID"] == product["productID"]
                   for a in registry["appearances"]):
                continue
            observation_id = f"reprint-appearance:{product['productID']}:{alias}"
            alias_record = {"provider": "bandai", "sourceID": f"{product['productID']}:{alias}"}
            result["observations"].append({
                "id": observation_id, "kind": "catalog", "language": "en", "alias": alias_record,
                "sourceURL": record["sourceURL"], "observedAt": record["observedAt"],
                "payloadSHA256": record["payloadSHA256"], "productEvidence": [product["productID"]],
                "printedEvidence": {"number": number, "sourceArtworkAlias": alias,
                                    "productLabel": " | ".join(row["productLabels"]),
                                    "sourceRole": "manufacturer-product-card-list"}})
            result["appearances"].append({"printingID": original["id"], "productID": product["productID"],
                                          "observationIDs": [observation_id]})
            result["aliasAttachments"].append({"printingID": original["id"], "alias": alias_record})
            ids.append(observation_id)
            stats["appearance"] += 1
    if ids:
        digest = sha256(json.dumps(sorted(ids)).encode()).hexdigest()[:16]
        result["inventories"].append({"provider": "bandai", "snapshotID": "reprint-appearances:" + digest,
                                      "paginationComplete": False, "observationIDs": sorted(ids)})
    return result, stats, held


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--products", type=Path, required=True, help="Reviewed product manifest")
    parser.add_argument("--bandai-captures", type=Path, required=True)
    parser.add_argument("--artwork-captures", type=Path, required=True)
    parser.add_argument("--market-captures", type=Path, required=True)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.report.exists():
        raise ValueError("Outputs must be fresh paths")
    market = TCGCSVSnapshot(args.market_captures, "CardScannerOnePieceReview/1.0", 0.15, offline=True)
    result, stats, held = resolve(json.loads(args.release.read_bytes()), json.loads(args.products.read_bytes()),
                                  ProductCapture(args.bandai_captures, offline=True),
                                  ProductCapture(args.artwork_captures, offline=args.offline), market)
    atomic_json(args.output, result)
    atomic_json(args.report, {"schemaVersion": 1, "stats": dict(stats), "held": held})
    print(dict(stats))


if __name__ == "__main__":
    main()
