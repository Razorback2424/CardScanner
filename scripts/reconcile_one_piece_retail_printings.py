#!/usr/bin/env python3
"""Reconcile exact Bandai presentations with retained English retail finish labels."""

import argparse
from collections import Counter, defaultdict
from contextlib import ExitStack
import fcntl
from functools import lru_cache
from hashlib import sha256
from itertools import chain
import json
from math import sqrt
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.parse import parse_qs, urljoin, urlsplit
from uuid import NAMESPACE_URL, uuid5

from audit_one_piece_coverage import PRINTED_NUMBER, compare, parse_cardlist
from capture_one_piece_products import (
    ProductCapture, TCGPLAYER_ARTWORK_URL, WEIRDWOLF_ARTWORK_URL, atomic_json, checked_url, next_retailer_page, safe_path,
)
from normalize_one_piece_sources import Document, one
from one_piece_eb05_retail import EB05_PRODUCT, eb05_listings
from one_piece_tcgcsv_capture import TCGCSVSnapshot
from reconcile_one_piece_launch_products import capture_index, checked_capture, load_products, names_agree, normalized_name


MARKET_ROOT = "https://tcgcsv.com/tcgplayer/68/"
PRB01_GROUP = "23496"
PRB01_MANGA_SPEC = "This card was reprinted from the original set without the original textured foil."
PROMO_GROUP = "17675"
PROMO_START = "https://coretcg.com/Products/0/68/17675/One-Piece-Promotion-Cards?l=144&stockStatus=0"
PROMO_SERIES = ("569901", "569801")
# Each alternate title names the same reviewed product. An artwork match and
# independent marketplace agreement are still required for the exact card.
PROMO_DISTRIBUTION_ALIASES = {
    "Included in FILM RED Promotion Card Set": "One Piece Film Red",
    "GIFT COLLECTION 2023 [GC-01]": "Gift Collection 2023",
    "Premium Card Collection -Best Selection-": "Premium Card Collection -Best Selection Vol. 1-",
    "Japanese 2nd Anniversary Set": "One Piece Japanese Version 2nd Anniversary Set",
    "Japanese 3rd ANNIVERSARY SET": "Japanese Version 3rd Anniversary Set",
    "ST15-20 Release Event": "ST15 - ST20 Release Event Pack",
    "CS 25-26 Top Player Pack 2": "CS 25-26 Top Player Pack Vol. 2",
    "ST-11 Uta Deck Battle Participation Pack": "Starter Deck 11: Uta Deck Battle",
    "Sealed Battle 2023 Vol.1": "Sealed Battle Kit Vol. 1",
    "Tournament Kit 2025 Vol.2": "Tournament Pack 2025 Vol. 2",
    "Illustration Box Vol.7": "One Piece Card Game Illustration Box Vol. 7",
    "Illustration Box Vol.8": "One Piece Card Game Illustration Box Vol. 8",
}
REFERENCE_REGION_ERROR_LIMIT = 0.019
COMPARISON_SIZE = (84, 117)
ARTWORK_REGIONS = ((4, 4, 80, 47), (4, 76, 80, 107), (4, 107, 80, 115))
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
    if not requested:
        return None
    matches = {label for label in labels if requested in {
        normalized_name(label.removeprefix("Included in ")),
        normalized_name(PROMO_DISTRIBUTION_ALIASES.get(label, "")),
    }}
    return next(iter(matches)) if len(matches) == 1 else None


def promotion_treatment(number, name, title, labels):
    for suffix in (" (Alternate Art)", " (Parallel)"):
        if title.endswith(suffix):
            pack = promotion_label(number, name, title.removesuffix(suffix), labels)
            return (pack, "Alternate artwork") if pack is not None else None
    pack = promotion_label(number, name, title, labels)
    return (pack, None) if pack is not None else None


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
    if not ranked or max(ranked[0][1]) > REFERENCE_REGION_ERROR_LIMIT:
        return None
    if len(ranked) > 1 and sum(ranked[1][1]) - sum(ranked[0][1]) < 0.060:
        return None
    return ranked[0][0]


def exact_digital_artwork_match(comparison, references, scores, scale=1):
    """Use matching digital renders to distinguish a localized mark from a sibling."""
    from PIL import ImageChops, ImageStat

    if len(references) < 2:
        return None
    # Ignore edge rounding. Retain the middle here because a digital reference
    # can carry the same watermark and a stamp visible through it.
    interior = tuple(edge * scale for edge in (3, 3, 81, 115))
    comparison = comparison.crop(interior)
    references = {key: image.crop(interior) for key, image in references.items()}
    matches = []
    for key, image in references.items():
        if max(scores[key]) > REFERENCE_REGION_ERROR_LIMIT:
            continue
        error = ImageChops.difference(comparison, image).convert("L")
        if ImageStat.Stat(error).mean[0] / 255 > REFERENCE_REGION_ERROR_LIMIT:
            continue
        distinctions = []
        for other, sibling in references.items():
            if other == key:
                continue
            difference = ImageChops.difference(image, sibling).convert("L")
            mask = difference.point(lambda pixel: 255 if pixel >= 30 else 0)
            count = mask.histogram()[255] // (scale * scale)
            if count < 20:
                break
            error_ratio = ImageStat.Stat(error, mask).mean[0] / ImageStat.Stat(difference, mask).mean[0]
            if error_ratio > 0.20:
                break
            distinctions.append((count, error_ratio))
        else:
            matches.append((key, min(count for count, _ in distinctions), max(ratio for _, ratio in distinctions)))
    return matches[0] if len(matches) == 1 else None


def photographic_artwork_match(comparison, references):
    """Compare distinct designs when a photo changes the color or lighting."""
    from PIL import ImageFilter

    if not references:
        return None

    def normalized_regions(image):
        luminance = image.convert("L").filter(ImageFilter.GaussianBlur(0.8))
        vectors = []
        for region in ARTWORK_REGIONS:
            pixels = list(luminance.crop(region).getdata())
            mean = sum(pixels) / len(pixels)
            centered = [pixel - mean for pixel in pixels]
            scale = sqrt(sum(pixel * pixel for pixel in centered))
            vectors.append([pixel / scale for pixel in centered] if scale else centered)
        return vectors

    def distances(first, second):
        return tuple(1 - sum(a * b for a, b in zip(left, right)) for left, right in zip(first, second))

    measured = normalized_regions(comparison)
    expected = {key: normalized_regions(image) for key, image in references.items()}
    ranking = sorted(((key, distances(measured, pixels)) for key, pixels in expected.items()),
                     key=lambda row: sum(row[1]))
    key, errors = ranking[0]
    if max(errors[:2]) > 0.12 or errors[2] > 0.35 or sum(errors) > 0.34:
        return None
    if len(ranking) == 1:
        # The lone reference still needs close agreement across the artwork
        # and text. The separately checked listing and product supply identity.
        return (key, errors) if sum(errors) <= 0.24 else None
    if sum(ranking[1][1]) - sum(errors) < 0.40:
        return None
    # Hold same-art siblings even if the photo's rank appears unambiguous.
    # Small differences may identify a stamp, block or footer revision.
    if any(sum(distances(expected[key], sibling)[:2]) < 0.30
           for other, sibling in expected.items() if other != key):
        return None
    return key, errors


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
        return promotion_treatment(numbers[0], name, product["name"], [label[0]]) == label
    return listing_treatment(numbers[0], name, product["name"]) == label


def reviewed_promo_artwork(listing, distribution, references, artwork, reviews):
    review = reviews.get(listing["imageProductID"])
    if review is None or (review["number"], review["distribution"], review["finish"]) != (
            listing["number"], distribution, listing["finish"]):
        return None
    reference = (review["series"], review["alias"])
    reference_url = references.get(reference)
    if (reference_url is not None and artwork[reference_url]["payloadSHA256"] == review["bandaiImageSHA256"]
            and artwork[listing["imageURL"]]["payloadSHA256"] == review["retailerImageSHA256"]):
        return reference
    return None


def treatment_matches_alias(label, alias, market_product, finish):
    if "_r" not in alias:
        return label != "Reprint"
    if label == "Reprint":
        return True
    # PRB-01 reissued some original manga artwork with a different finish.
    # The exact SKU identifies those reprints even though its title says Manga.
    return (label == "Manga" and finish == "foil" and market_product["groupId"] == int(PRB01_GROUP)
            and any(field["name"] == "Description" and PRB01_MANGA_SPEC in field["value"]
                    for field in market_product["extendedData"]))


def build_retail_additions(release, product_rules, bandai_root, retail_root, artwork_root, market, artwork_capture=None,
                           eb05_roots=(), promo_root=None, promo_photo_reviews=None):
    from io import BytesIO
    from PIL import Image, ImageChops, ImageStat

    def captures(root):
        return capture_index(json.loads((root / "capture-manifest.json").read_bytes())["captures"], "sourceURL")

    bandai = captures(bandai_root)
    retail = captures(retail_root) if retail_root is not None else {}
    artwork = (captures(artwork_root) if artwork_capture is None else
               capture_index(artwork_capture.manifest["captures"], "sourceURL"))

    def read_pixels(url, size=COMPARISON_SIZE):
        record = artwork.get(url)
        if record is None:
            if artwork_capture is None:
                return None
            parsed = urlsplit(url)
            bucket = {"product-images.tcgplayer.com": "tcgplayer", "en.onepiece-cardgame.com": "bandai",
                      "sortswift.nyc3.cdn.digitaloceanspaces.com": "cardboard-colosseum",
                      "cdn.shopify.com": "rocket-city-toys"}[parsed.netloc]
            if WEIRDWOLF_ARTWORK_URL.fullmatch(url):
                bucket = "weird-wolf-games"
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
                if size != COMPARISON_SIZE and (width < size[0] or height < size[1]):
                    return None
                return image.convert("RGB").resize(size, Image.Resampling.BILINEAR)
        except OSError:
            return None

    pixels = lru_cache(maxsize=4096)(read_pixels)

    def differences(retailer, official):
        diff = ImageChops.difference(retailer, official)
        return tuple(sum(ImageStat.Stat(diff.crop(region)).mean) / (3 * 255) for region in ARTWORK_REGIONS)

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
    promo_labels = defaultdict(set)
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
                    if len(row["productLabels"]) == 1:
                        promo_labels[row["number"]].add(row["productLabels"][0])

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
                label = promotion_treatment(number, names[number], listing["title"], promo_labels[number])
                if label is None or label[0] not in labels:
                    continue
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
            image_detail = "The retailer reference matches the exact Bandai presentation across three image regions."
            image_fields = {}
            if selected is None:
                digital = exact_digital_artwork_match(comparison, references, scores)
                if (digital is None and group_id == PRB01_GROUP and len(references) > 1
                        and any(max(errors) <= REFERENCE_REGION_ERROR_LIMIT for errors in scores.values())):
                    # Thin differences in PRB-01's finish renders disappear at
                    # thumbnail size. Apply the same checks at four times the resolution.
                    size = tuple(dimension * 4 for dimension in COMPARISON_SIZE)
                    detailed = read_pixels(listing["imageURL"], size)
                    siblings = {key: read_pixels(url, size) for key, url in art_urls.items()}
                    if detailed is not None and all(image is not None for image in siblings.values()):
                        digital = exact_digital_artwork_match(detailed, siblings, scores, scale=4)
                        if digital is not None:
                            image_fields["digitalComparisonScale"] = "4"
                if digital is not None:
                    selected, distinct_pixels, relative_error = digital
                    image_fields.update({"digitalComparisonDistinctPixels": str(distinct_pixels),
                                         "digitalComparisonMaxRelativeError": f"{relative_error:.4f}"})
                    image_detail = ("The retailer digital render matches the Bandai presentation at the regions "
                                    "that distinguish it from every official sibling.")
            if selected is None and promotion:
                photographic = photographic_artwork_match(comparison, references)
                if photographic is not None:
                    selected, errors = photographic
                    image_fields = {"photographicStructureErrors": ",".join(f"{error:.4f}" for error in errors)}
                    image_detail = "The retailer photo matches the distinct Bandai design across three image regions."
                elif promo_photo_reviews:
                    selected = reviewed_promo_artwork(listing, label[0], art_urls, artwork, promo_photo_reviews)
                    if selected is not None:
                        image_fields["artworkReview"] = "reviewed-photo-pair"
                        image_detail = "A visual review matched the English card photograph to this exact Bandai design."
            if selected is None:
                stats["ambiguous-artwork"] += 1
                continue
            if promotion:
                selected_series, alias = selected
                if selected_series != series:
                    continue
            else:
                alias = selected
            matches[alias].append((listing, receipt, label, scores[selected], (image_detail, image_fields)))
        for row in rows:
            alias, number = row["artworkAlias"], row["number"]
            evidence = matches.get(alias)
            if not evidence or row["status"] not in {"missing-printing-or-appearance", "held"}:
                continue
            identities = {(listing["finish"], label) for listing, _, label, _, _ in evidence}
            if len(identities) != 1 or len({listing["imageProductID"] for listing, _, _, _, _ in evidence}) != 1:
                stats["contradictory-retailer-listings"] += 1
                continue
            listing, receipt, (label, treatment), score, image_review = min(
                evidence, key=lambda value: (value[0]["provider"], value[0]["sourceID"]))
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
            elif (not treatment_matches_alias(label, alias, market_products[int(listing["imageProductID"])],
                                               listing["finish"])
                  or (not label and alias != number)):
                stats["unclear-retailer-treatment"] += 1
                continue
            elif label == "Manga" and "_r" in alias:
                treatment = "Manga artwork (non-textured foil)"
                image_review[1]["marketplacePrintingSpecification"] = PRB01_MANGA_SPEC
            identity = (printing_release, "one-piece:en:" + number, treatment)
            seen_presentations[identity] += 1
            if (series, alias) in candidate_matches:
                raise ValueError("Two retailer groups claim the same Bandai presentation")
            candidate_matches[(series, alias)] = (
                row, identity, list_source, image_source, listing, receipt, score, existing, distribution, image_review)

    result = {key: [] for key in ("artworks", "printings", "observations", "inventories", "finishUpdates")}
    evidence_ids = defaultdict(list)
    promo_products = {}
    for (_, alias), match in sorted(candidate_matches.items()):
        row, identity, list_source, image_source, listing, receipt, score, existing, distribution, image_review = match
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
        image_detail, image_fields = image_review
        fields.update(image_fields)
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
            ("artwork", render_id, image_detail),
            ("release", list_id, "Bandai lists this exact artwork in the reviewed release."),
            ("distribution" if distribution is not None else "treatment", finish_id,
             "The retailer title names the exact Bandai distribution." if distribution is not None else
             "The retailer title and uniquely matching official artwork identify the treatment."),
            ("finish", finish_id, "The retailer explicitly specifies the English printing's physical finish."),
        ]
        if distribution is not None and treatment is not None:
            evidence.append(("treatment", finish_id, "The retailer explicitly names the alternate artwork."))
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
        ids = sorted(ids)
        # Later reviews can derive additional observations from the same bytes.
        # Keep each reviewed membership reproducible without replacing the older inventory.
        membership = sha256(json.dumps(ids, separators=(",", ":")).encode()).hexdigest()
        result["inventories"].append({"provider": provider,
                                      "snapshotID": f"retail-artwork-review:{digest}:{membership}",
                                      "paginationComplete": False, "observationIDs": ids})
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
                        help="Retained Cardboard Colosseum, Rocket City Toys or Weird Wolf Games EB-05 product responses")
    parser.add_argument("--promo-retail-captures", type=Path, help="Retained CoreTCG promo pages for named Bandai products")
    parser.add_argument("--reviewed-promo-photos", type=Path, help="Visually reviewed pairs keyed by retailer image product ID")
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
    if args.reviewed_promo_photos and not args.promo_retail_captures:
        parser.error("Reviewed promo photos require the retained promo listings")
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
        reviews = json.loads(args.reviewed_promo_photos.read_bytes()) if args.reviewed_promo_photos else None
        result, stats = build_retail_additions(json.loads(args.release.read_bytes()), products,
                                               args.bandai_captures, args.retail_captures, args.artwork_captures,
                                               market, artwork_capture, args.eb05_retail_captures,
                                               args.promo_retail_captures, reviews)
        atomic_json(args.output, result)
    print(dict(sorted(stats.items())))


if __name__ == "__main__":
    main()
