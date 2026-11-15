#!/usr/bin/env python3
"""Read-only live Bandai/TCGCSV artwork comparison for an official One Piece set.

This is candidate discovery, NOT physical-printing, language, finish, or pricing authority.
Never publishes a catalog and never saves fetched artwork to the repository.
"""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import re
import time
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from PIL import Image, ImageChops, ImageStat

from audit_one_piece_coverage import parse_cardlist
from normalize_one_piece_sources import Document, one
from one_piece_tcgcsv_capture import validate_document
from reconcile_one_piece_retail_printings import (
    ARTWORK_REGIONS, COMPARISON_SIZE, exact_artwork_match, exact_digital_artwork_match,
)

USER_AGENT = "ScanStash-OnePiece-EvidenceAudit/1.0"
OFFICIAL_HOST = "en.onepiece-cardgame.com"
MARKET_HOSTS = {"tcgplayer-cdn.tcgplayer.com", "product-images.tcgplayer.com"}
MAX_BYTES = 6 * 1024 * 1024


class BoundedFetcher:
    def __init__(self, max_requests=200, delay=0.15):
        self.max_requests = max_requests
        self.delay = delay
        self.cache = {}
        self.receipts = {}

    def get(self, url, allowed_hosts):
        if url in self.cache:
            return self.cache[url]
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.hostname not in allowed_hosts or parsed.port is not None:
            raise ValueError("Unsupported evidence URL: " + url)
        if len(self.cache) >= self.max_requests:
            raise ValueError("Evidence request budget exceeded")
        time.sleep(self.delay)
        request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "image/*,application/json,text/html"})
        with urlopen(request, timeout=30) as response:
            final = urlsplit(response.geturl())
            if final.scheme != "https" or final.hostname not in allowed_hosts:
                raise ValueError("Evidence redirect left allowed host")
            raw = response.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError("Evidence exceeds 6 MiB limit")
        self.cache[url] = raw
        self.receipts[url] = {"sha256": sha256(raw).hexdigest(), "bytes": len(raw)}
        return raw


def image_or_reason(fetcher, url, hosts):
    if not url:
        return None, "no-recorded-image-url"
    try:
        raw = fetcher.get(url, hosts)
        with Image.open(BytesIO(raw)) as img:
            width, height = img.size
            if height < 200 or not 0.67 <= width / height <= 0.75 or width * height > 6_000_000:
                return None, "unsupported-image-dimensions"
            return img.convert("RGB").resize(COMPARISON_SIZE, Image.Resampling.BILINEAR), None
    except (ValueError, OSError, TimeoutError, ConnectionError) as error:
        return None, type(error).__name__
    except Exception as error:
        # Source/network outages are evidence gaps, never matching authority.
        return None, type(error).__name__


def region_errors(candidate, official):
    diff = ImageChops.difference(candidate, official)
    return tuple(sum(ImageStat.Stat(diff.crop(region)).mean) / (3 * 255)
                 for region in ARTWORK_REGIONS)


def near_threshold_artwork_match(scores):
    """Report a likely JPEG-scale match, never an approved printing.

    Compare sum and worst-region errors, and require clear separation from
    every sibling. This is intentionally *not* used by the publisher verifier.
    """
    ranked = sorted(scores.items(), key=lambda item: sum(item[1]))
    if not ranked:
        return None
    best_alias, errors = ranked[0]
    if max(errors) > 0.023 or sum(errors) > 0.056:
        return None
    if len(ranked) > 1 and sum(ranked[1][1]) - sum(errors) < 0.12:
        return None
    return best_alias


def official_images(raw, series):
    document = Document(raw).root
    urls = {}
    for modal in document.nodes("dl", "modalCol"):
        alias = modal.attrs.get("id", "")
        if not alias:
            continue
        images = [img.attrs["data-src"] for img in modal.nodes("img") if img.attrs.get("data-src")]
        if len(images) != 1:
            urls[alias] = None
            continue
        url = urljoin("https://" + OFFICIAL_HOST + "/cardlist/?series=" + series, images[0])
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or parsed.hostname != OFFICIAL_HOST or
                parsed.path != "/images/cardlist/card/" + alias + ".png"):
            urls[alias] = None
        else:
            urls[alias] = url
    return urls


def match_products(number, official_rows, products, image_loader):
    """Return candidates with comparison outcomes; no finish or printing approval."""
    references, source_errors = {}, {}
    for alias in sorted(row["artworkAlias"] for row in official_rows if row["number"] == number):
        image, error = image_loader("bandai", alias)
        if image is None:
            source_errors[alias] = error
        else:
            references[alias] = image
    incomplete = bool(source_errors)
    decisions = []
    for product in sorted(products, key=lambda p: p["productId"]):
        image, error = image_loader("market", product)
        result = {"productID": product["productId"], "title": product["name"],
                  "imageURL": product.get("imageUrl"), "decision": "unresolved"}
        if error:
            result.update(decision="market-image-unavailable", reason=error)
        elif incomplete:
            result.update(decision="official-sibling-image-unavailable",
                          missingAliases=sorted(source_errors))
        else:
            scores = {alias: region_errors(image, ref) for alias, ref in references.items()}
            selected = exact_artwork_match(scores)
            if selected is None and len(references) > 1:
                digital = exact_digital_artwork_match(image, references, scores)
                if digital is not None:
                    selected = digital[0]
            if selected is not None:
                result.update(decision="unique-artwork-candidate", matchedAlias=selected)
            else:
                near = near_threshold_artwork_match(scores)
                if near is not None:
                    result.update(decision="near-threshold-artwork-candidate", matchedAlias=near)
                else:
                    result["decision"] = "no-unique-artwork-match"
            result["regionErrors"] = {
                alias: [round(value, 5) for value in values] for alias, values in sorted(scores.items())
            }
        decisions.append(result)
    return decisions, source_errors


def audit(series, group, previews, fetcher):
    bandai_url = "https://" + OFFICIAL_HOST + "/cardlist/?series=" + series
    market_url = "https://tcgcsv.com/tcgplayer/68/" + str(group) + "/products"
    prices_url = "https://tcgcsv.com/tcgplayer/68/" + str(group) + "/prices"
    official_raw = fetcher.get(bandai_url, {OFFICIAL_HOST})
    rows = parse_cardlist(official_raw, series)
    official_urls = official_images(official_raw, series)
    source = validate_document(json.loads(fetcher.get(market_url, {"tcgcsv.com"})), market_url)
    price_source = validate_document(json.loads(fetcher.get(prices_url, {"tcgcsv.com"})), prices_url)
    products = [p for p in source["results"] if p.get("categoryId") == 68 and p.get("groupId") == group]
    finish_lanes = defaultdict(set)
    for price in price_source["results"]:
        finish_lanes[price["productId"]].add(price["subTypeName"])
    discoveries = {}
    prefix = "bandai-browse:" + series + ":"
    for key, url in previews.items():
        observation, sep, receipt_hash = key.partition("|")
        if sep and observation.startswith(prefix) and re.fullmatch(r"[0-9a-f]{64}", receipt_hash):
            discoveries[observation.removeprefix(prefix)] = url
    by_alias = {r["artworkAlias"]: r for r in rows}
    missing_discoveries = sorted(set(discoveries) - set(by_alias))
    if missing_discoveries:
        raise ValueError("Bundled discovery alias absent from current Bandai list: " + str(missing_discoveries))
    needed_numbers = {by_alias[alias]["number"] for alias in discoveries}
    selected_rows = [r for r in rows if r["number"] in needed_numbers]
    market_by_number = defaultdict(list)
    for product in products:
        values = [field["value"] for field in product.get("extendedData", [])
                  if field.get("name") == "Number"]
        if len(values) == 1 and values[0] in needed_numbers:
            market_by_number[values[0]].append(product)

    def loader(provider, obj):
        if provider == "bandai":
            url = official_urls.get(obj)
            if obj in discoveries and url and discoveries[obj].split("?")[0] != url.split("?")[0]:
                return None, "bundled-preview-disagrees-with-official-path"
            return image_or_reason(fetcher, url, {OFFICIAL_HOST})
        return image_or_reason(fetcher, obj.get("imageUrl"), MARKET_HOSTS)

    results_by_number = {}
    source_gaps = {}
    for number in sorted(needed_numbers):
        comparisons, gaps = match_products(number, selected_rows, market_by_number[number], loader)
        for item in comparisons:
            item["marketQuoteLanes"] = sorted(finish_lanes[item["productID"]])
        results_by_number[number] = comparisons
        source_gaps[number] = gaps

    aliases = []
    for alias in sorted(discoveries):
        number = by_alias[alias]["number"]
        same_art = [p for p in results_by_number[number]
                    if p.get("matchedAlias") == alias and p["decision"] in {
                        "unique-artwork-candidate", "near-threshold-artwork-candidate"}]
        status = ("multiple-products-claim-artwork" if len(same_art) > 1
                  else "unique-artwork-market-candidate" if len(same_art) == 1
                       and same_art[0]["decision"] == "unique-artwork-candidate"
                  else "near-threshold-artwork-market-candidate" if len(same_art) == 1
                  else "official-artwork-not-captured" if alias in source_gaps[number]
                  else "unresolved-in-live-image-comparison")
        aliases.append({"alias": alias, "number": number, "status": status,
                        "suggestedProductID": same_art[0]["productID"] if len(same_art) == 1 else None,
                        "artworkImageURL": official_urls.get(alias),
                        "sourceImageIssue": source_gaps[number].get(alias),
                        "candidates": results_by_number[number]})
    return {"schemaVersion": 1, "generatedAt": datetime.now(timezone.utc).isoformat(),
            "officialSeries": series, "tcgcsvGroup": group,
            "officialPresentations": len(rows), "discoveryObservations": len(discoveries),
            "limitations": [
                "This is a read-only artwork/market-product candidate comparison, not a printing verification.",
                "TCGCSV price lanes do not independently establish physical finish or language.",
                "A unique image match still needs independent source evidence and exact mapping review.",
                "A failed image request or strict image comparison is not proof the product is absent.",
            ],
            "aliases": aliases, "sourceReceipts": fetcher.receipts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--series", default="569205")
    parser.add_argument("--group", type=int, default=24820)
    parser.add_argument("--previews", type=Path,
                        default=Path("TradingCardScanner/OnePieceCatalogSeed/discovery-previews-v1.json"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.series.isdigit() or args.group <= 0 or args.output.exists():
        parser.error("Require numeric series and group, and a new output path")
    report = audit(args.series, args.group, json.loads(args.previews.read_text()), BoundedFetcher())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    counts = defaultdict(int)
    for row in report["aliases"]:
        counts[row["status"]] += 1
    print(json.dumps({"observations": len(report["aliases"]), "outcomes": dict(counts)}, sort_keys=True))


if __name__ == "__main__":
    main()
