#!/usr/bin/env python3
"""Add each TCGplayer promo product as its own physical printing.

Promotional cards are often handed out in tiers that share one artwork but
carry different stamps: Participant, Finalist and Winner copies, online and
offline regional copies, or an event card and its Winner copy. Collectors and
TCGplayer treat every one as a separate card, while Bandai's card list shows
at most one entry. This replay creates one printing per TCGplayer product in
the promo group, filed under a "One Piece Promotion Cards" product as TCGplayer
files them. The TCGplayer event text becomes the printing's distribution, and
a bracketed tier becomes its stamp.

A product becomes a printing only when all of the following hold:

* It has one printed number for a known card and exactly one Normal or Foil
  price lane. That lane is its finish evidence.
* Its title is the card name followed by one event qualifier and an optional
  tier.
* Its photo matches exactly one Bandai presentation of that number, from any
  series. A digital render must pass the strict region test; a photograph must
  pass the structural test, which holds siblings that share their art.
* No printing already names this TCGplayer product.
* No printing of the same card already uses that artwork. A stamped copy and
  an identical reprint look alike, and earlier reviews modelled some promo
  collections as the original printing, so those are held for review.

A photo that matches no Bandai presentation at all records art Bandai never
published; the photo becomes that printing's artwork evidence. A distribution
that prints an event stamp (``STAMPED_DISTRIBUTIONS``) may share the base art,
and its stamp may overlap the art beyond the strict comparison limit.

A Bandai promo-list entry that is still missing from the catalog is bound to one
of these printings only when its distribution name picks exactly one product:
by online or offline, and by its participation, finalist or champion/winner
tier. Otherwise its tier is the product without a Winner marker. An entry that
cannot be bound stays under "Printing needs review". A treatment-only qualifier
such as "(Alternate Art)" takes the bound Bandai distribution name, and is held
when nothing binds it.
"""

import argparse
from collections import Counter, defaultdict
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import re
from urllib.error import HTTPError
from uuid import NAMESPACE_URL, uuid5

from audit_one_piece_coverage import (
    NO_PHOTO_FIELD, NO_PHOTO_VALUE, UNPRICED_FIELD, UNPRICED_VALUE, compare, parse_cardlist,
)
from capture_one_piece_products import ProductCapture, atomic_json
from discover_one_piece_products import retained
from one_piece_tcgcsv_capture import TCGCSVSnapshot
from reconcile_one_piece_launch_products import names_agree, normalized_name
from reconcile_one_piece_retail_printings import (
    ARTWORK_REGIONS, COMPARISON_SIZE, MARKET_ROOT, PROMO_GROUP, PROMO_SERIES, REFERENCE_REGION_ERROR_LIMIT, TREATMENTS,
    exact_artwork_match, photographic_artwork_match,
)

RELEASE_ID = "product:tcgplayer-promotion-cards"
RELEASE_LABEL = "One Piece Promotion Cards"
TIERS = {"participant": "Participant", "finalist": "Finalist", "winner": "Winner", "judge": "Judge",
         "serial number": "Serial numbered", "serial numbered": "Serial numbered",
         "top player": "Top Player", "champion": "Champion"}
# Reviewed 2026-11-18 from marketplace photos: these distributions print an event
# stamp on the card face (JUDGE, WINNER, CHAMPIONSHIP, Top Player, Finalist,
# Treasure Cup, Regionals, ROUND1), so a copy on base art is still its own card.
# Premium collections, anniversary sets, deck reissues and welcome packs show
# no stamp and stay held: an earlier review modelled one as the original printing.
STAMPED_DISTRIBUTIONS = re.compile(
    r"judge|winner|champion|finalist|top player|treasure cup|regional|celebration pack|event pack"
    r"|tournament pack|participation pack|store championship|round 1|pre-release|release event"
    r"|anniversary winner|2-on-2|3-on-3|sealed battle|store qualifier", re.IGNORECASE)
STAMP_OVERLAP_LIMIT = 0.06
MARKETPLACE_ONLY_ART = 0.12
TITLE = re.compile(r"(?P<name>.+?)(?: \((?P<short>[0-9]{3})\))? \((?P<qualifier>[^()]+)\)(?: \[(?P<tier>[^\]]+)\])?")


def parse_title(number, name, title):
    """(qualifier, tier) for '<card name> (<event>) [<tier>]', else None."""
    match = TITLE.fullmatch(title)
    if not match or re.fullmatch(r"[0-9]{3}", match["qualifier"]) or not names_agree(number, name, match["name"]):
        return None
    tier = match["tier"]
    if tier is not None and tier.lower() not in TIERS:
        return None
    return match["qualifier"].strip(), TIERS[tier.lower()] if tier else None


def binding_choice(label, products):
    """Pick the one product a Bandai distribution name describes, or None."""
    words = normalized_name(label)
    chosen = list(products)
    for venue in ("online", "offline"):
        if venue in words:
            chosen = [p for p in chosen if venue in normalized_name(p["qualifier"])]
    if "participation" in words or "participant" in words:
        wanted = "Participant"
    elif "finalist" in words:
        wanted = "Finalist"
    elif "champion" in words or "winner" in words:
        wanted = "Winner"
    else:
        wanted = None
    if wanted is not None:
        tiered = [p for p in chosen if p["tier"] == wanted]
        chosen = tiered or [p for p in chosen if p["tier"] is None and wanted.lower() in normalized_name(p["qualifier"])]
    else:
        chosen = [p for p in chosen if p["tier"] is None and "winner" not in normalized_name(p["qualifier"])]
    return chosen[0] if len(chosen) == 1 else None


def build_promo_tiers(release, coverage, bandai, artwork_capture, market, group=PROMO_GROUP,
                      release_id=RELEASE_ID, release_label=RELEASE_LABEL, filed_reprints=False):
    """Replay one marketplace group. ``filed_reprints`` treats every product in a
    product group (deck sets, demo decks, revision packs, edition decks) as the
    reprinting product's own printing, as collectors and TCGplayer file them."""
    from PIL import Image, ImageChops, ImageStat

    registry = release["registry"]
    observations = {row["id"]: row for row in release["observations"]}
    artworks = {row["id"]: row for row in registry["artworks"]}
    names = {row["printedNumber"]: row["name"] for row in registry["canonicalCards"] if row["language"] == "en"}
    claimed = set()
    for printing in registry["printings"]:
        claimed |= {m["productID"] for m in printing["marketMappings"] if m["provider"] == "tcgplayer"}
        claimed |= {a["sourceID"] for a in printing["sourceAliases"] if a["provider"] == "tcgplayer"}
        for item in (printing.get("review") or {}).get("evidence", []):
            reference = observations[item["observationID"]]["printedEvidence"].get("retailerReferenceProductID")
            if reference:
                claimed.add(reference)
    def names_marketplace_product(printing):
        return any(a["provider"] == "tcgplayer" for a in printing["sourceAliases"]) or printing["marketMappings"] or any(
            observations[i["observationID"]]["printedEvidence"].get("retailerReferenceProductID")
            for i in (printing.get("review") or {}).get("evidence", []))
    filed_cards = {(printing["canonicalCardID"], printing.get("releaseID")) for printing in registry["printings"]
                   if printing["status"] != "superseded"}
    existing_distributions = {(printing["canonicalCardID"], normalized_name(printing["distributionLabel"]),
                               printing.get("stamp")) for printing in registry["printings"]
                              if printing["status"] != "superseded" and printing.get("distributionLabel")}
    unclaimed_promo_art = {(printing["canonicalCardID"], artworks[printing["artworkID"]].get("imageSHA256"))
                           for printing in registry["printings"] if printing["status"] != "superseded"
                           and printing.get("distributionLabel") and not names_marketplace_product(printing)}
    retained_art = {(printing["canonicalCardID"], artworks[printing["artworkID"]].get("imageSHA256"))
                    for printing in registry["printings"] if printing["status"] != "superseded"}

    # Every Bandai presentation of a number, from every retained series.
    sources = {}
    siblings = defaultdict(dict)
    rows_by_series = {}
    for series in coverage["series"]:
        url = "https://en.onepiece-cardgame.com/cardlist/?series=" + series["seriesID"]
        # The default series page may be retained under the series index filename.
        record, raw = retained(bandai, url, "bandai-" + series["seriesID"] + ".html")
        sources[series["seriesID"]] = record
        text = raw.decode("utf-8")
        rows_by_series[series["seriesID"]] = {row["artworkAlias"]: row for row in
                                              compare([{"seriesID": series["seriesID"],
                                                        "rows": parse_cardlist(raw, series["seriesID"])}], release)[0]["rows"]}
        for row in rows_by_series[series["seriesID"]].values():
            if not row["number"]:
                continue
            match = re.search(r'data-src="\.\./images/cardlist/card/' + re.escape(row["artworkAlias"]) + r'\.png\?([0-9]+)"', text)
            if match:
                siblings[row["number"]][(series["seriesID"], row["artworkAlias"])] = (
                    "https://en.onepiece-cardgame.com/images/cardlist/card/" + row["artworkAlias"] + ".png?" + match[1])

    def pixels(url, filename):
        try:
            record, raw = artwork_capture.capture(url, filename)
        except HTTPError as error:
            if error.code in {404, 410}:
                return None, None
            raise
        except ValueError as error:
            # An image the marketplace no longer serves leaves no retained bytes to replay.
            if str(error).startswith("offline capture missing: ") and "tcgplayer.com" in url:
                return None, None
            raise
        try:
            with Image.open(BytesIO(raw)) as image:
                width, height = image.size
                if height < 200 or not 0.67 <= width / height <= 0.75:
                    return record, None
                return record, image.convert("RGB").resize(COMPARISON_SIZE, Image.Resampling.BILINEAR)
        except OSError:
            return record, None

    products_url = MARKET_ROOT + group + "/products"
    listing_source = market.manifest["captures"][products_url]
    lanes = defaultdict(set)
    for row in market.fetch_json(MARKET_ROOT + group + "/prices")["results"]:
        lanes[row["productId"]].add(row["subTypeName"])
    stats, holds = Counter(), {}
    matched = defaultdict(list)
    for product in market.fetch_json(products_url)["results"]:
        product_id = str(product["productId"])
        numbers = [f["value"] for f in product.get("extendedData", []) if f["name"] == "Number"]
        def hold(reason):
            stats[reason] += 1
            holds[product_id] = reason
        if len(numbers) != 1 or numbers[0] not in names:
            continue
        number = numbers[0]
        if product_id in claimed:
            stats["already-a-printing"] += 1
            continue
        lane = lanes.get(product["productId"], set())
        # No lane at all means TCGplayer never priced it: a known, unpriced printing.
        if len(lane) > 1 or (lane and next(iter(lane)) not in {"Normal", "Foil"}):
            hold("finish-lane-not-single"); continue
        parsed = parse_title(number, names[number], product["name"])
        if parsed is None and filed_reprints and names_agree(
                number, names[number], re.sub(r"\s*\([0-9]{3}\)\s*$", "", product["name"])):
            parsed = (None, None)  # a plain title in its own product group
        if parsed is None:
            hold("title-not-card-event-tier"); continue
        refs = {}
        for key, url in siblings[number].items():
            record, image = pixels(url, f"bandai/{key[0]}-{key[1]}.png")
            refs[key] = (record, image)
        if not refs or any(image is None for _, image in refs.values()):
            hold("official-reference-image-missing"); continue
        image_url = f"https://product-images.tcgplayer.com/fit-in/600x600/{product_id}.jpg"
        retailer_record, comparison = pixels(image_url, f"tcgplayer/{product_id}.jpg")
        if comparison is None:
            canonical_id = "one-piece:en:" + number
            if filed_reprints and (canonical_id, release_id) in filed_cards:
                hold("card-already-filed-in-this-product"); continue
            if parsed[0] and (canonical_id, normalized_name(parsed[0]), parsed[1]) in existing_distributions:
                hold("same-event-and-tier-as-an-existing-printing"); continue
            item = {"product": product, "number": number, "qualifier": parsed[0], "tier": parsed[1],
                    "finish": next(iter(lane)).lower() if lane else None, "retailer": None, "scores": None}
            if filed_reprints and len(refs) == 1:
                # A reprint in its own product group, of a card with one official art.
                key = next(iter(refs))
                matched[key].append(dict(item, official=refs[key][0], review="single-official-art"))
            elif parsed[0] is None or parsed[0] in TREATMENTS:
                hold("marketplace-image-missing")
            else:
                # The product is documented but its art cannot be confirmed: a known gap.
                matched[("tcgplayer", product_id)].append(dict(item, official=None, review="no-photo", finish=None))
            continue
        scores = {key: tuple(sum(ImageStat.Stat(ImageChops.difference(comparison, image).crop(region)).mean) / (3 * 255)
                             for region in ARTWORK_REGIONS) for key, (_, image) in refs.items()}
        stamped = filed_reprints or STAMPED_DISTRIBUTIONS.search(parsed[0] or "") is not None or parsed[1] is not None
        canonical_id = "one-piece:en:" + number
        if filed_reprints and (canonical_id, release_id) in filed_cards:
            hold("card-already-filed-in-this-product"); continue
        if parsed[0] and (canonical_id, normalized_name(parsed[0]), parsed[1]) in existing_distributions:
            hold("same-event-and-tier-as-an-existing-printing"); continue
        selected, review = exact_artwork_match(scores), "digital"
        if selected is None:
            photographic = photographic_artwork_match(comparison, {key: image for key, (_, image) in refs.items()})
            selected, review = (photographic[0], "photographic") if photographic else (None, None)
        best = min(scores, key=lambda key: sum(scores[key]))
        if selected is None and stamped and max(scores[best]) <= STAMP_OVERLAP_LIMIT:
            # The printed stamp overlaps the art. Accept the best Bandai art when it is
            # clearly ahead, or when every close sibling is that same image.
            close = [key for key in scores if key != best and sum(scores[key]) - sum(scores[best]) < 0.09]
            def identical(a, b):
                diff = ImageChops.difference(refs[a][1], refs[b][1])
                return max(sum(ImageStat.Stat(diff.crop(region)).mean) / (3 * 255)
                           for region in ARTWORK_REGIONS) <= REFERENCE_REGION_ERROR_LIMIT
            if all(identical(best, key) for key in close):
                selected, review = min([best] + close), "stamp-overlap"
        if selected is None and min(max(value) for value in scores.values()) > MARKETPLACE_ONLY_ART:
            # No Bandai presentation resembles this art: Bandai never published it.
            if parsed[0] is None or parsed[0] in TREATMENTS or any(
                    normalized_name(row.get("distributionLabel") or "") == normalized_name(parsed[0])
                    for row in registry["printings"] if row["canonicalCardID"] == canonical_id):
                hold("marketplace-only-art-may-duplicate-a-printing"); continue
            selected, review = ("tcgplayer", product_id), "marketplace-only"
        if selected is None:
            hold("no-unique-artwork-match"); continue
        official_record = refs[selected][0] if review != "marketplace-only" else None
        if official_record and (canonical_id, official_record["payloadSHA256"]) in unclaimed_promo_art:
            # An existing promo printing with this art names no TCGplayer product yet;
            # this product may be that same card under another event name.
            hold("may-be-an-existing-promo-printing"); continue
        if official_record and (canonical_id, official_record["payloadSHA256"]) in retained_art and not stamped:
            # Same art as a catalog printing and no event stamp: an identical reissue
            # looks the same here, and earlier reviews modelled some as the same printing.
            hold("same-art-as-existing-printing-needs-review"); continue
        matched[selected].append({"product": product, "number": number, "qualifier": parsed[0], "tier": parsed[1],
                                  "finish": next(iter(lane)).lower() if lane else None, "official": official_record,
                                  "retailer": retailer_record, "review": review,
                                  "scores": scores[selected] if official_record else scores[best]})

    # Bind still-missing Bandai promo entries to exactly one matched product.
    bound = {}
    for series in PROMO_SERIES:
        for alias, row in rows_by_series.get(series, {}).items():
            candidates = matched.get((series, alias), [])
            if row["status"] != "missing-printing-or-appearance" or len(row["productLabels"]) != 1 or not candidates:
                continue
            choice = binding_choice(row["productLabels"][0], [
                {"qualifier": c["qualifier"], "tier": c["tier"], "id": c["product"]["productId"]} for c in candidates])
            if choice is not None:
                bound[str(choice["id"])] = (series, alias, row)

    result = {key: [] for key in ("artworks", "printings", "observations", "inventories")}
    result["products"] = [{"id": release_id, "label": release_label}]
    bandai_ids, market_ids = [], []
    for (series, alias), items in sorted(matched.items()):
        for item in items:
            product_id = str(item["product"]["productId"])
            binding = bound.get(product_id)
            distribution = item["qualifier"]
            treatment = None
            if distribution is None:
                pass  # plain title: the product group itself is the release
            elif filed_reprints and distribution in TREATMENTS:
                treatment, distribution = TREATMENTS[distribution], None
            elif distribution in TREATMENTS:
                if binding is None:
                    stats["treatment-only-title-without-bandai-entry"] += 1
                    holds[product_id] = "treatment-only-title-without-bandai-entry"
                    continue
                distribution = binding[2]["productLabels"][0].removeprefix("Included in ")
            source_id = f"{release_id}:{product_id}"
            official_alias = {"provider": "bandai", "sourceID": source_id}
            market_alias = {"provider": "tcgplayer", "sourceID": product_id}
            render_id, listing_id = source_id + ":render", source_id + ":marketplace"
            fields = {"sourceRole": "marketplace-promo-listing", "number": item["number"],
                      "name": item["product"]["name"],
                      **({"distribution": distribution} if distribution else {}),
                      **({"treatment": treatment} if treatment else {}),
                      **({"finishVariantID": item["finish"]} if item["finish"] else {UNPRICED_FIELD: UNPRICED_VALUE}),
                      "retailerReferenceProductID": product_id,
                      **({"retailerImageSHA256": item["retailer"]["payloadSHA256"]} if item["retailer"] else {}),
                      **({NO_PHOTO_FIELD: NO_PHOTO_VALUE} if item["review"] == "no-photo" else {}),
                      **({"matchedBandaiImageSHA256": item["official"]["payloadSHA256"],
                          "matchedBandaiArtworkAlias": alias} if item["official"] else {}),
                      **({"artworkRegionMeanErrors": ",".join(f"{e:.4f}" for e in item["scores"])}
                         if item["scores"] else {}),
                      "artworkComparison": item["review"]}
            if item["tier"]:
                fields["stamp"] = item["tier"]
            result["observations"].append({
                "id": listing_id, "kind": "catalog", "language": "en", "alias": market_alias,
                "sourceURL": products_url, "observedAt": listing_source["observedAt"],
                "payloadSHA256": listing_source["payloadSHA256"], "productEvidence": [release_id],
                "printedEvidence": fields})
            market_ids.append(listing_id)
            if item["official"]:
                result["observations"].append({
                    "id": render_id, "kind": "catalog", "language": "en", "alias": official_alias,
                    "sourceURL": item["official"]["sourceURL"], "observedAt": item["official"]["observedAt"],
                    "payloadSHA256": item["official"]["payloadSHA256"], "imageSHA256": item["official"]["payloadSHA256"],
                    "productEvidence": [release_id],
                    "printedEvidence": {"number": item["number"], "sourceArtworkAlias": alias,
                                        "sourceRole": "watermarked-digital-render"}})
                bandai_ids.append(render_id)
                art_hash = item["official"]["payloadSHA256"]
            elif item["review"] == "no-photo":
                render_id, art_hash = listing_id, None
            else:
                # Bandai never published this art; the marketplace photo is the only record.
                render_id = source_id + ":photo"
                result["observations"].append({
                    "id": render_id, "kind": "catalog", "language": "en", "alias": market_alias,
                    "sourceURL": item["retailer"]["sourceURL"], "observedAt": item["retailer"]["observedAt"],
                    "payloadSHA256": item["retailer"]["payloadSHA256"], "imageSHA256": item["retailer"]["payloadSHA256"],
                    "productEvidence": [release_id],
                    "printedEvidence": {"number": item["number"], "sourceRole": "marketplace-product-photo"}})
                market_ids.append(render_id)
                art_hash = item["retailer"]["payloadSHA256"]
            evidence = [("printedIdentity", listing_id, "TCGplayer lists this exact number as its own promo product."),
                        ("language", listing_id, "The marketplace lists this product in its English One Piece category."),
                        ("artwork", render_id, {
                            "marketplace-only": "Bandai never published this art; the marketplace photo records it.",
                            "stamp-overlap": "The marketplace photo shows this Bandai art under the event's printed stamp.",
                            "single-official-art": "The marketplace has no photo; Bandai publishes one art for this card.",
                            "no-photo": "The marketplace has no photo, so this printing's art is not confirmed.",
                        }.get(item["review"], "The marketplace image matches exactly one Bandai presentation of this number.")),
                        ("release", listing_id, f"TCGplayer files this card in its {release_label} group.")]
            if distribution:
                evidence.append(("distribution", listing_id, "The marketplace title names the event or product that distributed it."))
            if treatment:
                evidence.append(("treatment", listing_id, "The marketplace title names this treatment."))
            if item["finish"]:
                evidence.append(("finish", listing_id, "The marketplace lists only this finish lane for the exact product."))
            # A marketplace-only artwork has no Bandai record behind an official alias.
            aliases = [official_alias, market_alias] if item["official"] else [market_alias]
            if item["tier"]:
                evidence.append(("stamp", listing_id, "The marketplace title names the tier stamped on this copy."))
            if binding is not None:
                bound_series, bound_alias, row = binding
                list_id = f"{release_id}:{bound_series}:{bound_alias}:list"
                list_alias = {"provider": "bandai", "sourceID": f"{release_id}:{bound_series}:{bound_alias}"}
                source = sources[bound_series]
                result["observations"].append({
                    "id": list_id, "kind": "catalog", "language": "en", "alias": list_alias,
                    "sourceURL": source["sourceURL"], "observedAt": source["observedAt"],
                    "payloadSHA256": source["payloadSHA256"], "productEvidence": [release_id],
                    "printedEvidence": {"number": item["number"], "sourceArtworkAlias": bound_alias,
                                        "productLabel": row["productLabels"][0]}})
                bandai_ids.append(list_id)
                aliases.append(list_alias)
                evidence.append(("printedIdentity", list_id, "Bandai's promotion list names this card and distribution."))
                stats["bound-to-bandai-entry"] += 1
            artwork_id = str(uuid5(NAMESPACE_URL, source_id + "/artwork")).upper()
            result["artworks"].append({"id": artwork_id, "observationIDs": [render_id],
                                       **({"imageSHA256": art_hash} if art_hash else {})})
            printing = {"id": str(uuid5(NAMESPACE_URL, source_id + "/printing")).upper(),
                        "canonicalCardID": "one-piece:en:" + item["number"], "language": "en",
                        "artworkID": artwork_id, "releaseID": release_id,
                        "status": "verified" if item["finish"] else "provisional",
                        "supportedVariantIDs": [item["finish"]] if item["finish"] else [], "sourceAliases": aliases,
                        "marketMappings": [], "supersedes": [],
                        "review": {"reference": "https://www.tcgplayer.com/product/" + product_id,
                                   "evidence": [{"kind": k, "observationID": o, "detail": d} for k, o, d in evidence]}}
            if distribution:
                printing["distributionLabel"] = distribution
            if treatment:
                printing["treatment"] = treatment
            if item["tier"]:
                printing["stamp"] = item["tier"]
            result["printings"].append(printing)
            stats["verified-new" if item["finish"] else "known-unpriced-new"] += 1
    # Membership digests keep a later incremental run from replacing an earlier inventory.
    membership = sha256(json.dumps(sorted(market_ids + bandai_ids)).encode()).hexdigest()[:16]
    result["inventories"] = [
        {"provider": "tcgplayer", "snapshotID": f"tcgcsv-promo-tiers:{group}:{listing_source['payloadSHA256']}:{membership}",
         "paginationComplete": True, "observationIDs": sorted(market_ids)},
        {"provider": "bandai", "snapshotID": f"promo-tier-review:{listing_source['payloadSHA256']}:{membership}",
         "paginationComplete": False, "observationIDs": sorted(bandai_ids)}]
    result["inventories"] = [row for row in result["inventories"] if row["observationIDs"]]
    if not result["printings"]:
        result["products"] = []
        result["inventories"] = []
    return result, stats, holds


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--release", type=Path, required=True, help="Unsigned candidate")
    parser.add_argument("--coverage", type=Path, required=True, help="Coverage report for this candidate, all series")
    parser.add_argument("--bandai-captures", type=Path, required=True)
    parser.add_argument("--artwork-captures", type=Path, required=True)
    parser.add_argument("--market-captures", type=Path, required=True, help="Complete retained TCGCSV snapshot")
    parser.add_argument("--group", type=int, action="append", default=[],
                        help="Marketplace product group to replay as filed reprints; omit for the promo group")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.report.exists() or args.output == args.report:
        raise ValueError("Outputs must be fresh, distinct paths")
    market = TCGCSVSnapshot(args.market_captures, "CardScannerOnePieceReview/1.0", 0.15, offline=True)
    if market.manifest.get("complete") is not True or market.manifest.get("upstreamBuild") != market.upstream_build:
        raise ValueError("Promo tier review requires a complete retained daily TCGCSV snapshot")
    coverage = json.loads(args.coverage.read_bytes())
    if coverage.get("requestedSeries"):
        raise ValueError("Promo tier review needs a coverage report across every Bandai series")
    release = json.loads(args.release.read_bytes())
    bandai = ProductCapture(args.bandai_captures, offline=True)
    artwork = ProductCapture(args.artwork_captures, offline=args.offline)
    if not args.group:
        result, stats, holds = build_promo_tiers(release, coverage, bandai, artwork, market)
    else:
        names = {g["groupId"]: g["name"] for g in market.fetch_json(MARKET_ROOT + "groups")["results"]}
        result = {key: [] for key in ("artworks", "printings", "observations", "inventories", "products")}
        stats, holds = Counter(), {}
        for group in args.group:
            part, part_stats, part_holds = build_promo_tiers(
                release, coverage, bandai, artwork, market, group=str(group),
                release_id=f"product:tcgplayer-group:{group}", release_label=names[group], filed_reprints=True)
            for key in result:
                result[key] += part.get(key, [])
            stats.update(part_stats)
            holds.update(part_holds)
    atomic_json(args.output, result)
    atomic_json(args.report, {"schemaVersion": 1, "stats": dict(sorted(stats.items())), "held": dict(sorted(holds.items()))})
    print(dict(sorted(stats.items())))


if __name__ == "__main__":
    main()
