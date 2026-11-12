#!/usr/bin/env python3
"""Reconcile exact Bandai presentations with retained English retail finish labels."""

import argparse
from collections import Counter, defaultdict
from contextlib import ExitStack
import fcntl
from functools import lru_cache
from itertools import chain
import json
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.parse import parse_qs, urljoin, urlsplit
from uuid import NAMESPACE_URL, uuid5

from audit_one_piece_coverage import PRINTED_NUMBER, compare, parse_cardlist
from capture_one_piece_products import (
    ProductCapture, TCGPLAYER_ARTWORK_URL, atomic_json, checked_url, next_retailer_page, safe_path,
)
from normalize_one_piece_sources import Document, one
from one_piece_eb05_retail import EB05_PRODUCT, eb05_listings
from one_piece_tcgcsv_capture import TCGCSVSnapshot
from reconcile_one_piece_launch_products import capture_index, checked_capture, load_products, names_agree, normalized_name


MARKET_ROOT = "https://tcgcsv.com/tcgplayer/68/"
PROMO_GROUP = "17675"
PROMO_START = "https://coretcg.com/Products/0/68/17675/One-Piece-Promotion-Cards?l=144&stockStatus=0"
PROMO_SERIES = ("569901", "569801")
FINISH = re.compile(r"English - (Near Mint|Lightly Played|Moderately Played|Heavily Played|Damaged) - (Normal|Foil)")
TREATMENTS = {
    "Alternate Art": "Alternate artwork",
    "Box Topper": "Box topper artwork",
    "Full Art": "Full artwork",
    "Heroine Leader": "Heroine leader artwork",
    "Jolly Roger Foil": "Jolly Roger foil",
    "Kentaro Yabuki": "Kentaro Yabuki artwork",
    "Manga": "Manga artwork",
    "Pandaman Art": "Pandaman artwork",
    "Parallel": "Alternate artwork",
    "Pirate Foil": "Pirate foil",
    "Reprint": "Standard artwork",
    "SP": "Special artwork",
    "Super Alternate Art": "Super alternate artwork",
    "Super Leader Alternate Art": "Super leader alternate artwork",
    "Super Rare Alternate Art": "Super rare alternate artwork",
    "TR": "Treasure Rare artwork",
    "Textured Foil": "Textured foil",
    "Wanted Poster": "Wanted poster artwork",
}


def listing_treatment(number, name, title):
    if names_agree(number, name, title):
        return "", "Standard artwork"
    for label, treatment in TREATMENTS.items():
        suffix = " (" + label + ")"
        if title.endswith(suffix) and names_agree(number, name, title.removesuffix(suffix)):
            return label, treatment
    return None


def promotion_label(number, name, title, labels):
    qualifier = re.fullmatch(r"(.+) \(([^()]*)\)", title)
    if not qualifier or not names_agree(number, name, qualifier[1]):
        return None
    requested = normalized_name(qualifier[2])
    matches = {label for label in labels if normalized_name(label.removeprefix("Included in ")) == requested}
    return next(iter(matches)) if len(matches) == 1 else None


def retailer_listings(document, group_id):
    for card in document.nodes("div", "productCard"):
        numbers = {n.text() for n in card.nodes("span", "small") if PRINTED_NUMBER.fullmatch(n.text())}
        titles = list(card.nodes("a", "small"))
        lanes = [node.text() for node in card.nodes("div", "small") if node.text().startswith("English - ")]
        images = [node.attrs.get("src", "") for node in card.nodes("img", "productImage")]
        if len(numbers) != 1 or len(titles) != 1 or len(lanes) != 1 or len(images) != 1:
            continue
        path = titles[0].attrs.get("href", "")
        listing = re.fullmatch(r"/Products/([1-9][0-9]*)/68/" + re.escape(group_id) + r"/[^?#]+", path)
        image = TCGPLAYER_ARTWORK_URL.fullmatch(images[0])
        lane = FINISH.fullmatch(lanes[0])
        if listing and image and lane:
            yield {"provider": "coretcg", "number": numbers.pop(), "title": titles[0].text(), "path": path,
                   "sourceID": f"{group_id}:{listing[1]}", "finish": lane[2].lower(), "lane": lanes[0],
                   "imageURL": images[0], "imageProductID": image[1]}


def coretcg_listings(retail_root, receipts, source_url, group_id):
    page = 1
    while True:
        receipt = receipts[checked_url(source_url, "coretcg.com")]
        document = Document(checked_capture(retail_root, receipt)).root
        for listing in retailer_listings(document, group_id):
            yield listing, receipt
        next_page = next_retailer_page(document, source_url, group_id, page)
        if next_page is None:
            return
        page, source_url = next_page


def exact_artwork_match(scores):
    """Three independent regions compare the whole design around Bandai's watermark."""
    ranked = sorted(scores.items(), key=lambda item: sum(item[1]))
    if not ranked or max(ranked[0][1]) > 0.019:
        return None
    if len(ranked) > 1 and sum(ranked[1][1]) - sum(ranked[0][1]) < 0.060:
        return None
    return ranked[0][0]


def market_agrees(listing, label, name, products, finishes, promotion=False):
    """Screen for contradictory marketplace metadata without creating finish authority or a quote."""
    product_id = int(listing["imageProductID"])
    product = products.get(product_id)
    if product is None or finishes.get(product_id) != {listing["finish"]}:
        return False
    numbers = [row["value"] for row in product.get("extendedData", []) if row["name"] == "Number"]
    if numbers != [listing["number"]]:
        return False
    if promotion:
        return promotion_label(numbers[0], name, product["name"], [label[0]]) == label[0]
    return listing_treatment(numbers[0], name, product["name"]) == label


def build_retail_additions(release, product_rules, bandai_root, retail_root, artwork_root, market, artwork_capture=None,
                           eb05_roots=(), promo_root=None):
    from io import BytesIO
    from PIL import Image, ImageChops, ImageStat

    def captures(root):
        return capture_index(json.loads((root / "capture-manifest.json").read_bytes())["captures"], "sourceURL")

    bandai = captures(bandai_root)
    retail = captures(retail_root) if retail_root is not None else {}
    artwork = (captures(artwork_root) if artwork_capture is None else
               capture_index(artwork_capture.manifest["captures"], "sourceURL"))

    @lru_cache(maxsize=4096)
    def pixels(url):
        record = artwork.get(url)
        if record is None:
            if artwork_capture is None:
                return None
            parsed = urlsplit(url)
            bucket = {"product-images.tcgplayer.com": "tcgplayer", "en.onepiece-cardgame.com": "bandai",
                      "sortswift.nyc3.cdn.digitaloceanspaces.com": "cardboard-colosseum",
                      "cdn.shopify.com": "rocket-city-toys"}[parsed.netloc]
            try:
                record, raw = artwork_capture.capture(url, bucket + "/" + Path(parsed.path).name)
            except HTTPError as error:
                if error.code in {404, 410}:
                    return None
                raise
            artwork[url] = record
        else:
            raw = checked_capture(artwork_root, record)
        try:
            with Image.open(BytesIO(raw)) as image:
                width, height = image.size
                if height < 200 or not 0.67 <= width / height <= 0.75 or width * height > 6_000_000:
                    return None
                return image.convert("RGB").resize((84, 117), Image.Resampling.BILINEAR)
        except OSError:
            return None

    def differences(retailer, official):
        diff = ImageChops.difference(retailer, official)
        regions = ((4, 4, 80, 47), (4, 76, 80, 107), (4, 107, 80, 115))
        return tuple(sum(ImageStat.Stat(diff.crop(region)).mean) / (3 * 255) for region in regions)

    registry = release["registry"]
    printings = {row["id"]: row for row in registry["printings"]}
    artworks = {row["id"]: row for row in registry["artworks"]}
    used_aliases = {(alias["provider"], alias["sourceID"])
                    for row in printings.values() for alias in row["sourceAliases"]}
    known_market_ids = {mapping["productID"] for row in printings.values() for mapping in row["marketMappings"]
                        if mapping["provider"] == "tcgplayer"}
    products_by_id = {product["id"]: product for product in registry["products"]}
    names = {row["printedNumber"]: row["name"] for row in registry["canonicalCards"] if row["language"] == "en"}
    seen_presentations = Counter((row["releaseID"], row["canonicalCardID"], row.get("treatment"))
                                 for row in printings.values() if row["status"] == "verified" and row.get("releaseID"))
    candidate_matches = {}
    stats = Counter()

    @lru_cache(maxsize=None)
    def load_series(manufacturer_url):
        list_url = checked_url(manufacturer_url, "en.onepiece-cardgame.com")
        series = one(parse_qs(urlsplit(list_url).query).get("series", []), "Bandai series")
        source = bandai[list_url]
        raw = checked_capture(bandai_root, source)
        inventory = {"seriesID": series, "rows": parse_cardlist(raw, series)}
        numbered_aliases = {row["artworkAlias"] for row in inventory["rows"] if row["number"]}
        renders = {}
        for modal in Document(raw).root.nodes("dl", "modalCol"):
            alias = modal.attrs.get("id")
            if alias not in numbered_aliases:
                continue
            image = one((img for img in modal.nodes("img") if "data-src" in img.attrs), "official reference image")
            url = checked_url(urljoin(list_url, image.attrs["data-src"]), "en.onepiece-cardgame.com")
            if urlsplit(url).path == f"/images/cardlist/card/{alias}.png":
                renders[alias] = url
        return series, source, compare([inventory], release)[0]["rows"], renders

    grouped_sources = defaultdict(list)
    for product in product_rules["products"]:
        source_url, group_id = product["retailerStartURL"], product["retailerGroupID"]
        if source_url in retail:
            key = product["productID"], group_id, product["manufacturerListURL"]
            grouped_sources[key].append(coretcg_listings(retail_root, retail, source_url, group_id))
    if eb05_roots:
        if EB05_PRODUCT[0] not in products_by_id:
            raise ValueError("EB-05 needs its Bandai discovery product in the baseline registry")
        grouped_sources[EB05_PRODUCT].append(eb05_listings(eb05_roots))
    promo_renders = defaultdict(dict)
    known_artwork = set()
    if promo_root is not None:
        known_artwork = {(row["canonicalCardID"], artworks[row["artworkID"]].get("imageSHA256"))
                         for row in printings.values()}
        retained_promos = list(coretcg_listings(promo_root, captures(promo_root), PROMO_START, PROMO_GROUP))
        for series in PROMO_SERIES:
            url = "https://en.onepiece-cardgame.com/cardlist/?series=" + series
            grouped_sources[(f"product:bandai-series:{series}", PROMO_GROUP, url)].append(retained_promos)
            _, _, rows, renders = load_series(url)
            for row in rows:
                if row["number"]:
                    alias = row["artworkAlias"]
                    promo_renders[row["number"]][(series, alias)] = renders.get(alias)

    for (release_id, group_id, manufacturer_url), sources in grouped_sources.items():
        promotion = group_id == PROMO_GROUP
        market_products = capture_index((row for row in market.fetch_json(MARKET_ROOT + group_id + "/products")["results"]
                                         if row.get("categoryId") == 68 and row.get("groupId") == int(group_id)), "productId")
        market_finishes = defaultdict(set)
        for row in market.fetch_json(MARKET_ROOT + group_id + "/prices")["results"]:
            market_finishes[row["productId"]].add(row["subTypeName"].lower())
        series, list_source, rows, render_urls = load_series(manufacturer_url)
        by_number = defaultdict(list)
        for row in rows:
            if row["number"]:
                by_number[row["number"]].append(row)
        matches = defaultdict(list)
        for listing, receipt in chain.from_iterable(sources):
            number = listing["number"]
            family = by_number[number]
            if not family or all(row["status"] == "verified" for row in family) or number not in names:
                continue
            if promotion:
                labels = {row["productLabels"][0] for row in family if len(row["productLabels"]) == 1
                          and row["status"] == "missing-printing-or-appearance"}
                pack = promotion_label(number, names[number], listing["title"], labels)
                if pack is None:
                    continue
                label = (pack, None)
                art_urls = promo_renders[number]
            else:
                label = listing_treatment(number, names[number], listing["title"])
                if label is None:
                    stats["unrecognized-retailer-title"] += 1
                    continue
                art_urls = {row["artworkAlias"]: render_urls.get(row["artworkAlias"]) for row in family}
            comparison = pixels(listing["imageURL"])
            references = {key: pixels(url) if url is not None else None for key, url in art_urls.items()}
            if comparison is None or any(image is None for image in references.values()):
                stats["unavailable-reference-image"] += 1
                continue
            scores = {alias: differences(comparison, image) for alias, image in references.items()}
            selected = exact_artwork_match(scores)
            if selected is None:
                stats["ambiguous-artwork"] += 1
                continue
            if promotion:
                selected_series, alias = selected
                if selected_series != series:
                    continue
                matches[alias].append((listing, receipt, label, scores[selected]))
            else:
                matches[selected].append((listing, receipt, label, scores[selected]))
        for row in rows:
            alias, number = row["artworkAlias"], row["number"]
            evidence = matches.get(alias)
            if not evidence or row["status"] not in {"missing-printing-or-appearance", "held"}:
                continue
            identities = {(listing["finish"], label) for listing, _, label, _ in evidence}
            if len(identities) != 1 or len({listing["imageProductID"] for listing, _, _, _ in evidence}) != 1:
                stats["contradictory-retailer-listings"] += 1
                continue
            listing, receipt, (label, treatment), score = min(evidence, key=lambda value: (value[0]["provider"], value[0]["sourceID"]))
            if ((listing["provider"], listing["sourceID"]) in used_aliases or listing["imageProductID"] in known_market_ids
                    or ("Foil" in label and listing["finish"] != "foil")):
                stats["conflicting-source-identity"] += 1
                continue
            if not market_agrees(listing, (label, treatment), names[number], market_products, market_finishes, promotion):
                stats["unconfirmed-marketplace-crosscheck"] += 1
                continue
            image_source = artwork[render_urls[alias]]
            existing = printings[row["printingIDs"][0]] if row["status"] == "held" else None
            distribution = None
            printing_release = release_id
            if promotion:
                if existing is not None or row["productLabels"] != [label]:
                    stats["promo-distribution-mismatch"] += 1
                    continue
                if ("one-piece:en:" + number, image_source["payloadSHA256"]) in known_artwork:
                    stats["promo-existing-artwork-needs-appearance-review"] += 1
                    continue
                distribution = label.removeprefix("Included in ")
                key = uuid5(NAMESPACE_URL, "https://en.onepiece-cardgame.com/cardlist/#pack/" + normalized_name(distribution))
                printing_release = f"product:bandai-promo:{key}"
                if printing_release in products_by_id and products_by_id[printing_release]["label"] != distribution:
                    stats["promo-distribution-mismatch"] += 1
                    continue
            elif existing is not None:
                if (listing["provider"] != "coretcg" or existing["status"] != "provisional" or existing["supportedVariantIDs"]
                        or existing["releaseID"] != release_id or existing.get("review") is None
                        or artworks[existing["artworkID"]].get("imageSHA256") != image_source["payloadSHA256"]):
                    stats["held-identity-needs-review"] += 1
                    continue
                treatment = existing.get("treatment")
            elif ((label == "Reprint") != ("_r" in alias) or (not label and alias != number)):
                stats["unclear-retailer-treatment"] += 1
                continue
            identity = (printing_release, "one-piece:en:" + number, treatment)
            seen_presentations[identity] += 1
            if (series, alias) in candidate_matches:
                raise ValueError("Two retailer groups claim the same Bandai presentation")
            candidate_matches[(series, alias)] = (
                row, identity, list_source, image_source, listing, receipt, score, existing, distribution)

    result = {key: [] for key in ("artworks", "printings", "observations", "inventories", "finishUpdates")}
    evidence_ids = defaultdict(list)
    promo_products = {}
    for (_, alias), match in sorted(candidate_matches.items()):
        row, identity, list_source, image_source, listing, receipt, score, existing, distribution = match
        release_id, canonical_id, treatment = identity
        if seen_presentations[identity] != 1:
            stats["indistinguishable-printing-label"] += 1
            continue
        source_id = f"{release_id}:{alias}"
        official = {"provider": "bandai", "sourceID": source_id}
        merchant = {"provider": listing["provider"], "sourceID": listing["sourceID"]}
        render_id = source_id + ":render"
        list_id = source_id + ":list"
        finish_id = source_id + ":retailer-finish"

        def observe(observation_id, alias_value, source, fields, image_hash=None):
            observation = {"id": observation_id, "kind": "catalog", "language": "en", "alias": alias_value,
                           "sourceURL": source["sourceURL"], "observedAt": source["observedAt"],
                           "payloadSHA256": source["payloadSHA256"], "productEvidence": [release_id],
                           "printedEvidence": dict(fields, number=row["number"], sourceArtworkAlias=alias)}
            if image_hash is not None:
                observation["imageSHA256"] = image_hash
            result["observations"].append(observation)
            evidence_ids[(alias_value["provider"], source["payloadSHA256"])].append(observation_id)

        fields = {"sourceRole": "retailer-exact-printing-specification", "finishVariantID": listing["finish"],
                  "retailerListingPath": listing["path"], "retailerTitle": listing["title"], "retailerLane": listing["lane"],
                  "retailerReferenceProductID": listing["imageProductID"],
                  "retailerImageSHA256": artwork[listing["imageURL"]]["payloadSHA256"],
                  "matchedBandaiImageSHA256": image_source["payloadSHA256"],
                  "artworkRegionMeanErrors": ",".join(f"{error:.4f}" for error in score)}
        if treatment is not None:
            fields["treatment"] = treatment
        if distribution is not None:
            fields["distribution"] = distribution
        observe(finish_id, merchant, receipt, fields)
        if existing is not None:
            result["finishUpdates"].append({"printingID": existing["id"], "observationID": finish_id})
            stats["verified-existing"] += 1
            continue
        observe(list_id, official, list_source, {"productLabel": " | ".join(row["productLabels"])})
        observe(render_id, official, image_source, {"sourceRole": "watermarked-digital-render"},
                image_source["payloadSHA256"])
        artwork_id = str(uuid5(NAMESPACE_URL, f"{list_source['sourceURL']}#{source_id}/artwork")).upper()
        printing_id = str(uuid5(NAMESPACE_URL, f"{list_source['sourceURL']}#{source_id}/printing")).upper()
        result["artworks"].append({"id": artwork_id, "imageSHA256": image_source["payloadSHA256"],
                                   "observationIDs": [render_id]})
        evidence = [
            ("printedIdentity", list_id, "Exact collector number and artwork alias in the English Bandai product list."),
            ("language", finish_id, "The retailer explicitly lists this printing in English."),
            ("artwork", render_id, "The retailer reference matches the exact Bandai presentation across three image regions."),
            ("release", list_id, "Bandai lists this exact artwork in the reviewed release."),
            ("distribution" if distribution is not None else "treatment", finish_id,
             "The retailer title names the exact Bandai distribution." if distribution is not None else
             "The retailer title and uniquely matching official artwork identify the treatment."),
            ("finish", finish_id, "The retailer explicitly specifies the English printing's physical finish."),
        ]
        result["printings"].append({"id": printing_id, "canonicalCardID": canonical_id, "language": "en",
                                    "artworkID": artwork_id, "releaseID": release_id, "treatment": treatment,
                                    "status": "verified", "supportedVariantIDs": [listing["finish"]],
                                    "sourceAliases": [official, merchant], "marketMappings": [], "supersedes": [],
                                    "review": {"reference": urljoin(receipt["sourceURL"], listing["path"]),
                                               "evidence": [{"kind": kind, "observationID": oid, "detail": detail}
                                                            for kind, oid, detail in evidence]}})
        if distribution is not None:
            result["printings"][-1]["distributionLabel"] = distribution
            if release_id not in products_by_id:
                product = {"id": release_id, "label": distribution}
                if promo_products.setdefault(release_id, product) != product:
                    raise ValueError("Two official labels claim the same promo product")
        stats["verified-new"] += 1
    for (provider, digest), ids in sorted(evidence_ids.items()):
        result["inventories"].append({"provider": provider, "snapshotID": "retail-artwork-review:" + digest,
                                      "paginationComplete": False, "observationIDs": sorted(ids)})
    if promo_products:
        result["products"] = list(promo_products.values())
    return result, stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, required=True, help="Unsigned candidate with the reviewed release registry")
    parser.add_argument("--products", type=Path)
    parser.add_argument("--bandai-captures", type=Path, required=True)
    parser.add_argument("--retail-captures", type=Path)
    parser.add_argument("--eb05-retail-captures", type=Path, action="append", default=[],
                        help="Retained Cardboard Colosseum or Rocket City Toys EB-05 product responses")
    parser.add_argument("--promo-retail-captures", type=Path, help="Retained CoreTCG promo pages for named Bandai products")
    parser.add_argument("--artwork-captures", type=Path, required=True)
    parser.add_argument("--market-captures", type=Path, required=True, help="Retained category 68 TCGCSV snapshot")
    parser.add_argument("--fetch-missing-artwork", action="store_true",
                        help="Capture missing artwork references from the supplied product pages")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if (args.products is None) != (args.retail_captures is None):
        parser.error("--products and --retail-captures must be supplied together")
    if args.products is None and not args.eb05_retail_captures and args.promo_retail_captures is None:
        parser.error("Supply booster, EB-05, or promo captures")
    if args.output.exists():
        raise ValueError("Retail printing additions already exist")
    market = TCGCSVSnapshot(args.market_captures, "CardScannerOnePieceReview/1.0", 0.15, offline=True)
    if market.manifest.get("complete") is not True or market.manifest.get("upstreamBuild") != market.upstream_build:
        raise ValueError("Marketplace cross-check requires a complete retained daily snapshot")
    market.finish()
    with ExitStack() as scope:
        artwork_capture = None
        if args.fetch_missing_artwork:
            args.artwork_captures.mkdir(parents=True, exist_ok=True)
            lock = scope.enter_context(safe_path(args.artwork_captures, ".product-capture.lock").open("a"))
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            artwork_capture = ProductCapture(args.artwork_captures)
        products = load_products(args.products) if args.products else {"products": []}
        result, stats = build_retail_additions(json.loads(args.release.read_bytes()), products,
                                               args.bandai_captures, args.retail_captures, args.artwork_captures,
                                               market, artwork_capture, args.eb05_retail_captures, args.promo_retail_captures)
        atomic_json(args.output, result)
    print(dict(sorted(stats.items())))


if __name__ == "__main__":
    main()
