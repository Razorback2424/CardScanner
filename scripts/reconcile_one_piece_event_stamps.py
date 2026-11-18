#!/usr/bin/env python3
"""Add stamped event-pack printings (Pre-Release, Release Event, Anniversary).

Each English pre-release, release-event and anniversary-tournament pack holds
stamped copies of one booster's Common and Uncommon cards. Collectors and
TCGplayer treat every stamped copy as its own product in a dedicated group
(for example "Paramount War Pre-Release Cards"), separate from the booster.

A rule in ``publisher/one-piece/event-stamp-products.json`` pins one event.
A stamped printing is added only when all of the following hold:

* The retained official English Bandai event page still states the rule's
  exact specification lines, which give the stamp and the number of card types.
* The marketplace group lists exactly that many numbered products from the
  rule's prefixes. Each has a plain card title, one Normal price lane and a
  unique number.
* Bandai's retained card list for the rule's series shows the base
  presentation with a Common or Uncommon rarity, and that base presentation is
  a single verified printing.
* The marketplace photo, when one exists, matches that printing's official Bandai render
  across the three comparison regions used by the retail replay. A stamp can
  overlap the art enough to miss that limit. Such a pair is accepted only
  from ``--reviewed-photos``, a visual review keyed by marketplace product
  that pins both exact image hashes.

An event that fails a group-level check is held in full. A card that fails
a card-level check is held alone; its marketplace product stays unaccounted,
so coverage certification keeps its card family open. Outputs are
reviewed additions for ``audit_one_piece_coverage.py --reviewed-additions``.
No prices, market mappings or new artwork images are created; the stamped
printing displays the base Bandai render, and its stamp is a printed field.
"""

import argparse
from collections import Counter, defaultdict
from hashlib import sha256
import html
from io import BytesIO
import json
from pathlib import Path
import re
from urllib.error import HTTPError
from uuid import NAMESPACE_URL, uuid5

from audit_one_piece_coverage import UNPRICED_FIELD, UNPRICED_VALUE, compare, parse_cardlist
from capture_one_piece_products import ProductCapture, atomic_json
from discover_one_piece_products import retained
from normalize_one_piece_sources import Document
from one_piece_tcgcsv_capture import TCGCSVSnapshot
from reconcile_one_piece_retail_printings import (
    ARTWORK_REGIONS, COMPARISON_SIZE, REFERENCE_REGION_ERROR_LIMIT, listing_treatment,
)

MARKET_ROOT = "https://tcgcsv.com/tcgplayer/68/"
SPECIFICATION_ROLE = "manufacturer-event-pack-specification"
LISTING_ROLE = "marketplace-event-stamp-listing"


def page_text(raw):
    """Visible text of an official page with markup removed and whitespace collapsed."""
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", raw.decode("utf-8"))))


def rarities(raw):
    """Bandai rarity for each numbered presentation alias in a retained card list."""
    result = {}
    for modal in Document(raw).root.nodes("dl", "modalCol"):
        spans = [span.text() for info in modal.nodes(cls="infoCol") for span in info.nodes("span")]
        if len(spans) >= 2:
            result[modal.attrs.get("id", "")] = spans[1]
    return result


def validate_rule(rule):
    fields = {"productID", "label", "releaseDate", "marketplaceGroupID", "eventURL", "specification",
              "types", "series", "prefixes", "rarities", "stamp"}
    if set(rule) != fields or not rule["productID"].startswith("event:") or not rule["stamp"].strip():
        raise ValueError("Invalid event stamp rule: " + str(rule.get("productID")))
    if not rule["eventURL"].startswith("https://en.onepiece-cardgame.com/events/") or not rule["specification"]:
        raise ValueError("Event rules need an official English Bandai event page: " + rule["productID"])
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", rule["releaseDate"]) or type(rule["types"]) is not int:
        raise ValueError("Event rules need a release date and type count: " + rule["productID"])


def compare_images(retailer_raw, official_raw):
    from PIL import Image, ImageChops, ImageStat

    def load(raw):
        with Image.open(BytesIO(raw)) as image:
            width, height = image.size
            if height < 200 or not 0.67 <= width / height <= 0.75:
                return None
            return image.convert("RGB").resize(COMPARISON_SIZE, Image.Resampling.BILINEAR)
    retailer, official = load(retailer_raw), load(official_raw)
    if retailer is None or official is None:
        return None
    diff = ImageChops.difference(retailer, official)
    return tuple(sum(ImageStat.Stat(diff.crop(region)).mean) / (3 * 255) for region in ARTWORK_REGIONS)


def official_render(printing, artworks, observations):
    artwork = artworks[printing["artworkID"]]
    for observation_id in sorted(artwork["observationIDs"]):
        row = observations.get(observation_id)
        if (row and row["alias"]["provider"] == "bandai" and row.get("imageSHA256") == artwork.get("imageSHA256")
                and row["sourceURL"].startswith("https://en.onepiece-cardgame.com/images/")):
            return artwork, row
    return artwork, None


def build_event_stamps(release, rules, bandai, events, artwork_capture, market, photo_reviews=None):
    registry = release["registry"]
    observations = {row["id"]: row for row in release["observations"]}
    artworks = {row["id"]: row for row in registry["artworks"]}
    printings = {row["id"]: row for row in registry["printings"]}
    names = {row["printedNumber"]: row["name"] for row in registry["canonicalCards"] if row["language"] == "en"}
    claimed = {alias["sourceID"] for row in registry["printings"] for alias in row.get("sourceAliases", [])
               if alias["provider"] == "tcgplayer"}
    result = {key: [] for key in ("products", "artworks", "printings", "observations", "inventories")}
    report, stats = [], Counter()

    for rule in rules["events"]:
        validate_rule(rule)
        product_id, stamp, group = rule["productID"], rule["stamp"], str(rule["marketplaceGroupID"])
        entry = {"productID": product_id, "label": rule["label"], "accepted": [], "held": {}, "eventHeld": None}
        report.append(entry)
        page, page_raw = events.capture(rule["eventURL"], "event-" + product_id.removeprefix("event:") + ".html")
        text = page_text(page_raw)
        missing = [line for line in rule["specification"] if line not in text]
        if missing:
            entry["eventHeld"] = "official-specification-changed: " + " | ".join(missing)
            continue
        products_url = MARKET_ROOT + group + "/products"
        listing_source = market.manifest["captures"][products_url]
        lanes = defaultdict(set)
        for row in market.fetch_json(MARKET_ROOT + group + "/prices")["results"]:
            lanes[row["productId"]].add(row["subTypeName"])
        candidates = []
        for row in market.fetch_json(products_url)["results"]:
            numbers = [field["value"] for field in row.get("extendedData", []) if field["name"] == "Number"]
            if len(numbers) == 1 and any(numbers[0].startswith(prefix + "-") for prefix in rule["prefixes"]):
                candidates.append((numbers[0], row))
        counts = Counter(number for number, _ in candidates)
        if len(candidates) != rule["types"] or any(count > 1 for count in counts.values()):
            entry["eventHeld"] = f"marketplace-group-has-{len(candidates)}-numbered-products-for-{rule['types']}-types"
            continue

        base = {}
        for series in rule["series"]:
            url = "https://en.onepiece-cardgame.com/cardlist/?series=" + series
            # The default series page may be retained under the series index filename.
            _, raw = (retained(bandai, url, "bandai-" + series + ".html") if hasattr(bandai, "manifest")
                      else bandai.capture(url, "bandai-" + series + ".html"))
            rarity = rarities(raw)
            for row in compare([{"seriesID": series, "rows": parse_cardlist(raw, series)}], release)[0]["rows"]:
                if row["number"] and row["artworkAlias"] == row["number"]:
                    base[row["number"]] = (row, rarity.get(row["artworkAlias"]), url)

        accepted = []
        for number, product in sorted(candidates):
            if str(product["productId"]) in claimed:
                continue  # an earlier run already added this stamped printing
            def hold(reason):
                entry["held"][number] = reason
                stats[reason] += 1
            row, rarity, list_url = base.get(number, (None, None, None))
            if number not in names:
                hold("unknown-canonical-card"); continue
            if row is None or rarity not in rule["rarities"]:
                hold("bandai-base-presentation-not-common-or-uncommon"); continue
            if row["status"] != "verified" or len(row["printingIDs"]) != 1:
                hold("base-printing-not-uniquely-verified"); continue
            if listing_treatment(number, names[number], product["name"]) != ("", "Standard artwork"):
                hold("marketplace-title-not-plain"); continue
            unpriced = not lanes[product["productId"]]
            if not unpriced and lanes[product["productId"]] != {"Normal"}:
                hold("marketplace-finish-lane-not-normal-only"); continue
            base_printing = printings[row["printingIDs"][0]]
            artwork, render = official_render(base_printing, artworks, observations)
            if render is None:
                hold("no-official-render-for-base-printing"); continue
            official_record, official_raw = artwork_capture.capture(
                render["sourceURL"], "bandai/" + artwork["imageSHA256"] + ".png")
            if official_record["payloadSHA256"] != artwork["imageSHA256"]:
                hold("official-render-bytes-changed"); continue
            image_url = f"https://product-images.tcgplayer.com/fit-in/600x600/{product['productId']}.jpg"
            try:
                retailer_record, retailer_raw = artwork_capture.capture(image_url, f"tcgplayer/{product['productId']}.jpg")
            except HTTPError as error:
                if error.code not in {404, 410}:
                    raise
                retailer_record = retailer_raw = None
            except ValueError as error:
                if not str(error).startswith("offline capture missing: "):
                    raise
                retailer_record = retailer_raw = None
            if retailer_raw is None:
                # Bandai's page already defines the population as this set's own cards,
                # so a missing marketplace photo removes corroboration, not identity.
                accepted.append((number, product, base_printing, artwork, render, None, None, False, unpriced))
                stats["accepted-without-marketplace-photo"] += 1
                continue
            errors = compare_images(retailer_raw, official_raw)
            review = (photo_reviews or {}).get(str(product["productId"]))
            reviewed = (review is not None and review.get("number") == number
                        and review.get("productID") == product_id
                        and review.get("retailerImageSHA256") == retailer_record["payloadSHA256"]
                        and review.get("bandaiImageSHA256") == artwork["imageSHA256"])
            if errors is None or (max(errors) > REFERENCE_REGION_ERROR_LIMIT and not reviewed):
                hold("marketplace-photo-does-not-match-base-artwork"); continue
            accepted.append((number, product, base_printing, artwork, render, retailer_record, errors,
                             max(errors) > REFERENCE_REGION_ERROR_LIMIT, unpriced))
        if not accepted:
            entry["eventHeld"] = "no-card-passed"
            continue

        specification_id = product_id + ":specification"
        bandai_ids, market_ids = [specification_id], []
        result["observations"].append({
            "id": specification_id, "kind": "catalog", "language": "en",
            "alias": {"provider": "bandai", "sourceID": rule["eventURL"]},
            "sourceURL": rule["eventURL"], "observedAt": page["observedAt"], "payloadSHA256": page["payloadSHA256"],
            "productEvidence": [product_id],
            "printedEvidence": {"sourceRole": SPECIFICATION_ROLE, "stamp": stamp,
                                "specification": " ".join(rule["specification"]), "rarities": ",".join(rule["rarities"])}})
        result["products"].append({"id": product_id, "label": rule["label"], "releaseDate": rule["releaseDate"]})
        for number, product, base_printing, artwork, render, retailer_record, errors, visual, unpriced in accepted:
            source_id = f"{product_id}:{number}"
            render_id, listing_id = source_id + ":render", source_id + ":marketplace"
            official_alias = {"provider": "bandai", "sourceID": source_id}
            market_alias = {"provider": "tcgplayer", "sourceID": str(product["productId"])}
            result["observations"].append({
                "id": render_id, "kind": "catalog", "language": "en", "alias": official_alias,
                "sourceURL": render["sourceURL"], "observedAt": render["observedAt"],
                "payloadSHA256": artwork["imageSHA256"], "imageSHA256": artwork["imageSHA256"],
                "productEvidence": [product_id],
                "printedEvidence": {"number": number, "sourceArtworkAlias": number,
                                    "sourceRole": "watermarked-digital-render"}})
            result["observations"].append({
                "id": listing_id, "kind": "catalog", "language": "en", "alias": market_alias,
                "sourceURL": products_url, "observedAt": listing_source["observedAt"],
                "payloadSHA256": listing_source["payloadSHA256"], "productEvidence": [product_id],
                "printedEvidence": {"sourceRole": LISTING_ROLE, "number": number, "name": product["name"],
                                    "stamp": stamp,
                                    **({UNPRICED_FIELD: UNPRICED_VALUE} if unpriced else {"finishVariantID": "normal"}),
                                    "retailerReferenceProductID": str(product["productId"]),
                                    "marketplaceGroupID": group,
                                    "matchedBandaiImageSHA256": artwork["imageSHA256"],
                                    **({"retailerImageSHA256": retailer_record["payloadSHA256"],
                                        "artworkRegionMeanErrors": ",".join(f"{error:.4f}" for error in errors)}
                                       if retailer_record else {"marketplacePhoto": "none"}),
                                    **({"artworkReview": "reviewed-photo-pair"} if visual else {})}})
            bandai_ids.append(render_id)
            market_ids.append(listing_id)
            artwork_id = str(uuid5(NAMESPACE_URL, rule["eventURL"] + "#" + number + "/artwork")).upper()
            printing_id = str(uuid5(NAMESPACE_URL, rule["eventURL"] + "#" + number + "/printing")).upper()
            result["artworks"].append({"id": artwork_id, "imageSHA256": artwork["imageSHA256"],
                                       "observationIDs": [render_id]})
            evidence = [
                ("printedIdentity", listing_id, "The marketplace lists this exact number in the event's stamped card group."),
                ("language", specification_id, "The official English Bandai event page specifies this English pack."),
                ("artwork", render_id, "A visual review matched the stamped marketplace photo to the base Bandai art."
                 if visual else "The marketplace photo matches the base Bandai render across three image regions."
                 if retailer_record else "Bandai's event page states the stamped cards are this set's own cards; "
                 "the marketplace has no photo."),
                ("release", specification_id, "Bandai's event page defines the stamped card population of this pack."),
                ("stamp", specification_id, "Bandai's event page names the stamp that every card in this pack carries."),
            ]
            if not unpriced:
                evidence.append(("finish", listing_id, "The marketplace lists only a Normal finish lane for this stamped card."))
            result["printings"].append({
                "id": printing_id, "canonicalCardID": base_printing["canonicalCardID"], "language": "en",
                "artworkID": artwork_id, "releaseID": product_id, "stamp": stamp,
                # Never sold on TCGplayer: the printing is known but its finish is not.
                "status": "provisional" if unpriced else "verified",
                "supportedVariantIDs": [] if unpriced else ["normal"], "sourceAliases": [official_alias, market_alias],
                "marketMappings": [], "supersedes": [],
                "review": {"reference": rule["eventURL"],
                           "evidence": [{"kind": kind, "observationID": oid, "detail": detail}
                                        for kind, oid, detail in evidence]}})
            entry["accepted"].append(number)
        stats["verified-new"] += sum(1 for item in accepted if not item[-1])
        stats["known-unpriced-new"] += sum(1 for item in accepted if item[-1])
        # Membership digests keep a later incremental run from replacing an earlier inventory.
        membership = sha256(json.dumps(sorted(bandai_ids + market_ids)).encode()).hexdigest()[:16]
        result["inventories"].append({"provider": "bandai", "snapshotID": f"event-stamp-review:{product_id}:{membership}",
                                      "paginationComplete": False, "observationIDs": sorted(bandai_ids)})
        # The TCGCSV group export is a complete inventory of that group.
        result["inventories"].append({"provider": "tcgplayer",
                                      "snapshotID": f"tcgcsv:{group}:{listing_source['payloadSHA256']}:{membership}",
                                      "paginationComplete": True, "observationIDs": sorted(market_ids)})
    return result, stats, report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--release", type=Path, required=True, help="Unsigned candidate")
    parser.add_argument("--rules", type=Path, required=True)
    parser.add_argument("--bandai-captures", type=Path, required=True, help="Retained Bandai card-list capture root")
    parser.add_argument("--event-captures", type=Path, required=True, help="Bandai event page capture root")
    parser.add_argument("--artwork-captures", type=Path, required=True)
    parser.add_argument("--market-captures", type=Path, required=True, help="Complete retained TCGCSV snapshot")
    parser.add_argument("--reviewed-photos", type=Path,
                        help="Visually reviewed stamped photo pairs keyed by marketplace product ID")
    parser.add_argument("--offline", action="store_true", help="Replay retained captures only")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.report.exists() or args.output == args.report:
        raise ValueError("Outputs must be fresh, distinct paths")
    market = TCGCSVSnapshot(args.market_captures, "CardScannerOnePieceReview/1.0", 0.15, offline=True)
    if market.manifest.get("complete") is not True or market.manifest.get("upstreamBuild") != market.upstream_build:
        raise ValueError("Event stamp review requires a complete retained daily TCGCSV snapshot")
    release = json.loads(args.release.read_bytes())
    result, stats, report = build_event_stamps(
        release, json.loads(args.rules.read_bytes()), ProductCapture(args.bandai_captures, offline=True),
        ProductCapture(args.event_captures, offline=args.offline),
        ProductCapture(args.artwork_captures, offline=args.offline), market,
        json.loads(args.reviewed_photos.read_bytes())["pairs"] if args.reviewed_photos else None)
    atomic_json(args.output, result)
    atomic_json(args.report, {"schemaVersion": 1, "events": report})
    print(dict(sorted(stats.items())))


if __name__ == "__main__":
    main()
