#!/usr/bin/env python3
"""Retain the complete official ordinary-product inventory for bulk review.

Outputs are discovery evidence, not reviewed physical printings. Neither card
numbers nor TCGplayer groups allocate ownership IDs or imply completeness.
"""
import argparse
from datetime import date, datetime
import fcntl
import json
from pathlib import Path
import re
from urllib.parse import parse_qs, urljoin, urlsplit
from copy import deepcopy

from capture_one_piece_products import ProductCapture, atomic_json, checked_url
from normalize_one_piece_sources import Document

PREFIX = re.compile(r"(?:PRB|OP|ST|EB)-?\d{2}")
ALIAS = re.compile(r"((?:PRB|OP|ST|EB)\d{2}-\d{3}|P-\d{3})(?:_p\d+)?")
INDEX = "https://en.onepiece-cardgame.com/products/"
SERIES_INDEX = "https://en.onepiece-cardgame.com/cardlist/?series=569117"


def prefixes(text):
    return list(dict.fromkeys(m.group().replace("-", "") for m in PREFIX.finditer(text)))


def retained(capture, url, filename, identity=None):
    # Discovery reuses reviewed filenames/IDs instead of duplicating responses.
    records = [r for r in capture.manifest["captures"] + capture.external["captures"]
               if r["sourceURL"] == url]
    if records:
        record = records[0]
        if identity and record.get("id") is None:
            # The default series page may already be retained as the series
            # index. Attach its catalog ID after checking the same retained bytes.
            capture.capture(url, record["rawFile"])
            if record not in capture.manifest["captures"] or any(r.get("id") == identity for r in capture.manifest["captures"] + capture.external["captures"]):
                raise ValueError("cannot attach duplicate or external capture identity")
            record["id"] = identity
            atomic_json(capture.path, capture.manifest)
        return capture.capture(url, record["rawFile"], record.get("id"))
    return capture.capture(url, filename, identity)


def ordinary_product_links(document, base):
    result = {}
    for link in document.nodes("a"):
        href = link.attrs.get("href", "")
        if not href:
            continue
        url = urljoin(base, href)
        parsed = urlsplit(url)
        detail_path = parsed.path.endswith((".html", ".php")) or re.fullmatch(r"/products/(?:boosters|decks)/(?:op|st|eb|prb)\d{2}/", parsed.path)
        if parsed.netloc != "en.onepiece-cardgame.com" or not parsed.path.startswith("/products/") or not detail_path:
            continue
        codes = prefixes(link.text())
        if codes:
            checked_url(url, "en.onepiece-cardgame.com")
            if url in result:
                result[url]["prefixes"] = list(dict.fromkeys(result[url]["prefixes"] + codes))
                result[url]["indexLabel"] += " | " + link.text()
            else:
                result[url] = {"url": url, "indexLabel": link.text(), "prefixes": codes}
    return result


def discover(capture, reviewed, groups, as_of):
    _, raw = retained(capture, INDEX, "product-index-page1.html")
    pages, pending, products = {}, {1: INDEX}, {}
    while pending:
        page = min(pending)
        url = pending.pop(page)
        _, raw = retained(capture, url, "product-index-page" + str(page) + ".html")
        document = Document(raw).root
        pages[page] = url
        for target, product in ordinary_product_links(document, url).items():
            if target in products:
                products[target]["prefixes"] = list(dict.fromkeys(products[target]["prefixes"] + product["prefixes"]))
            else:
                products[target] = product
        for link in document.nodes("a"):
            target = urljoin(url, link.attrs.get("href", ""))
            parsed = urlsplit(target)
            query = parse_qs(parsed.query)
            if parsed.netloc != "en.onepiece-cardgame.com" or parsed.path != "/products/" or set(query) != {"page"}:
                continue
            values = query["page"]
            if len(values) != 1 or not values[0].isdigit():
                raise ValueError("invalid official index pagination")
            number = int(values[0])
            if not 1 <= number <= 100:
                raise ValueError("official index page budget exceeded")
            if number not in pages:
                pending[number] = target
    if set(pages) != set(range(1, max(pages) + 1)) or not products:
        raise ValueError("official product index inventory gap")

    for index, product in enumerate(products.values(), 1):
        _, raw = retained(capture, product["url"], "product-discovery-" + urlsplit(product["url"]).path.removeprefix("/products/").strip("/").replace("/", "-") + ".capture")
        document = Document(raw).root
        statuses = []
        for box in document.nodes(cls="prodStatusBox"):
            headings = list(box.nodes(cls="prodStatusTit"))
            contents = list(box.nodes(cls="prodStatusContents"))
            if len(headings) == len(contents) == 1:
                statuses.append({"heading": headings[0].text(), "value": contents[0].text()})
        product["sourceSpecifications"] = statuses
        product["cardListURLs"] = sorted({checked_url(urljoin(product["url"], a.attrs["href"]), "en.onepiece-cardgame.com")
                                         for a in document.nodes("a") if "/cardlist/?series=" in a.attrs.get("href", "")})
        print("Product evidence", index, "/", len(products), product["prefixes"], flush=True)

    _, raw = retained(capture, SERIES_INDEX, "cardlist-series-index.html")
    options = []
    for option in Document(raw).root.nodes("option"):
        codes = prefixes(option.text())
        if codes and option.attrs.get("value"):
            series_id = option.attrs["value"]
            if not series_id.isdigit():
                raise ValueError("invalid official series ID")
            options.append({"seriesID": series_id, "label": option.text(), "prefixes": codes})
    if not options or len({o["seriesID"] for o in options}) != len(options):
        raise ValueError("missing or duplicate official series")
    known = {p["prefix"]: p for p in reviewed["products"]}
    for index, series in enumerate(options, 1):
        primary = series["prefixes"][0]
        url = "https://en.onepiece-cardgame.com/cardlist/?series=" + series["seriesID"]
        record, raw = retained(capture, url, "bandai-" + primary.lower() + ".html", "bandai-" + primary.lower())
        aliases = []
        for modal in Document(raw).root.nodes("dl", "modalCol"):
            alias = modal.attrs.get("id", "")
            match = ALIAS.fullmatch(alias)
            if match:
                aliases.append({"printedNumber": match.group(1), "artworkAlias": alias})
        if not aliases or len({a["artworkAlias"] for a in aliases}) != len(aliases):
            raise ValueError("missing or duplicate official numbered artwork: " + primary)
        series.update({"sourceURL": url, "captureID": record.get("id"), "rawFile": record["rawFile"],
                       "payloadSHA256": record["payloadSHA256"], "artworks": aliases,
                       "reviewedProductID": known.get(primary, {}).get("productID"),
                       "officialProducts": [p for p in products.values() if primary in p["prefixes"]],
                       "marketGroupCandidates": [g for g in groups["results"]
                           if primary in prefixes(g.get("abbreviation", "")) or primary in prefixes(g["name"])]})
        series["reviewRequired"] = []
        if not series["officialProducts"]:
            series["reviewRequired"].append("official-product-page-not-linked")
        if not series["marketGroupCandidates"]:
            series["reviewRequired"].append("independent-product-group-not-found")
        if len(series["prefixes"]) > 1:
            series["reviewRequired"].append("combined-release-number-families")
        if primary.startswith("PRB") or any(a["printedNumber"].split("-")[0] != primary for a in aliases):
            series["reviewRequired"].append("product-scoped-reprints-or-special-artwork")
        print("Series evidence", index, "/", len(options), primary, len(aliases), "artworks", flush=True)
    linked = {p["url"] for s in options for p in s["officialProducts"]}
    return {"schemaVersion": 1, "purpose": "bulk-ordinary-product-discovery", "asOf": as_of,
            "physicalCoverageComplete": False, "officialIndexPages": [pages[n] for n in sorted(pages)],
            "series": options, "productsWithoutSeries": [p for p in products.values() if p["url"] not in linked],
            "reviewedProducts": reviewed["products"],
            "limitations": ["Discovery does not verify release dates, finish, physical UUID joins, image rights or market mappings.",
                             "All product-scoped reprints and combined releases require reviewed reconciliation."]}


def draft_manifest(inventory):
    """Prepare the entire batch for evidence review; never adopt the corpus."""
    result = {"schemaVersion": 1, "reviewDate": inventory["asOf"],
              "reviewStatus": "draft-requires-physical-evidence-review",
              "products": deepcopy(inventory["reviewedProducts"])}
    deferred = []
    for series in inventory["series"]:
        if series["reviewedProductID"]:
            continue
        prefix = series["prefixes"][0]
        groups = [g for g in series["marketGroupCandidates"]
                  if re.fullmatch(r"(?:PRB|OP|ST|EB)-?\d{2}(?:-?(?:EB)?\d{2})?", g.get("abbreviation", ""))]
        dates = set()
        for product in series["officialProducts"]:
            for value in re.findall(r"Release Date ([A-Za-z]+ \d{1,2}, \d{4})", product["indexLabel"]):
                dates.add(datetime.strptime(value, "%B %d, %Y").date().isoformat())
        if len(groups) != 1 or len(dates) != 1:
            deferred.append({"prefix": prefix, "reason": "release-date-or-ordinary-group-needs-review",
                             "seriesID": series["seriesID"], "physicalCoverageComplete": False})
            continue
        group, release_date = groups[0], next(iter(dates))
        slug = re.sub(r"[^A-Za-z0-9]+", "-", group["name"]).strip("-")
        by_number = {}
        for artwork in series["artworks"]:
            by_number.setdefault(artwork["printedNumber"], []).append(artwork["artworkAlias"])
        cards, held = [], []
        for number, aliases in sorted(by_number.items()):
            is_deck = prefix.startswith("ST")
            if number in aliases:
                # Foreign numbered base rows (e.g. EB04 in OP14/15/17) are
                # retained as release-specific rows, not collapsed by number.
                selected = number
            elif is_deck and len(aliases) == 1:
                selected = aliases[0]
            else:
                held.append({"printedNumber": number, "artworkAliases": aliases,
                             "reason": "parallel-or-reprint-treatment-needs-review"})
                continue
            cards.append({"printedNumber": number, "artworkAlias": selected,
                          "isReprint": is_deck and not number.startswith(prefix + "-"),
                          "excludedArtworkAliases": [a for a in aliases if a != selected]})
        if not cards:
            deferred.append({"prefix": prefix, "reason": "no-unambiguous-standard-artwork",
                             "seriesID": series["seriesID"], "physicalCoverageComplete": False})
            continue
        result["products"].append({
            "productID": "product:" + prefix.lower() + "-" + slug.lower() + "-" + release_date[:4],
            "label": group["name"] + " · " + prefix,
            "releaseDate": release_date, "prefix": prefix,
            "manufacturerCaptureID": series["captureID"], "manufacturerListURL": series["sourceURL"],
            "retailerGroupID": str(group["groupId"]),
            "retailerStartURL": "https://coretcg.com/Products/0/68/" + str(group["groupId"]) + "/" + slug + "?l=144&stockStatus=0",
            "retailerCaptureFiles": [prefix.lower() + "-retailer-all.html"], "cards": cards,
            "releaseEvidenceURLs": [p["url"] for p in series["officialProducts"]],
            "retailerLocatorEvidence": "Constructed category/group route from retained TCGCSV group; verify captured response before reconciliation.",
            "heldArtworkReview": held,
            "physicalCoverageComplete": False,
        })
    return result, {"schemaVersion": 1, "physicalCoverageComplete": False,
                    "deferredSeries": deferred,
                    "productsWithoutSeries": inventory["productsWithoutSeries"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-root", type=Path, required=True)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--groups", type=Path, required=True)
    parser.add_argument("--official-captures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--as-of", required=True)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--draft-products", type=Path,
                        help="Write an unadopted complete-batch manifest and adjacent scope-gap ledger")
    args = parser.parse_args()
    date.fromisoformat(args.as_of)
    if args.output.exists():
        raise ValueError("discovery output already exists")
    if args.draft_products and (args.draft_products.exists() or args.draft_products.with_suffix(".scope.json").exists()):
        raise ValueError("draft products output already exists")
    capture = ProductCapture(args.capture_root, offline=args.offline,
                             official_manifest=json.loads(args.official_captures.read_text()))
    with (capture.root / ".product-capture.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = discover(capture, json.loads(args.products.read_text()), json.loads(args.groups.read_text()), args.as_of)
        atomic_json(args.output, result)
        if args.draft_products:
            products, scope = draft_manifest(result)
            atomic_json(args.draft_products, products)
            atomic_json(args.draft_products.with_suffix(".scope.json"), scope)
    print("Retained bulk discovery:", args.output)


if __name__ == "__main__":
    main()
