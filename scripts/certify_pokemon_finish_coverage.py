#!/usr/bin/env python3
"""Compare one bundled Pokémon set with TCGCSV, then certify a reviewed report.

Resolutions use {finishes, citation, reason} keyed by card ID. A market-only
product outside the set may be resolved with {exclude: true, citation, reason}.
Regenerate any changed checklist slots before shipping a new certificate.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import tempfile
import unicodedata
from urllib.error import URLError
from urllib.parse import urlsplit

from audit_pokemon_finish_repairs import ROOT, ledger, minimum_table
from market_price_feeds import digest, read_http, stamp, validate_response

SNAPSHOT = Path("TradingCardScanner/PokemonChecklistSnapshot")
EVIDENCE = Path("docs/research/pokemon-finish-coverage")
MARKER = "https://tcgcsv.com/last-updated.txt"
STANDARD = (
    "Each numbered checklist card must agree with the matching TCGplayer products on exact finishes, "
    "or have a cited resolution. Every conflict, unmatched number and Normal review must be resolved. "
    "Market listings are evidence of membership. Physical or retail evidence resolves disagreements."
)
LANES = {"normal": "normal", "holofoil": "holo", "reverse holofoil": "reverse"}
PATTERNS = {
    "poke ball": "pokeBall", "master ball": "masterBall", "dusk ball": "duskBall",
    "friend ball": "friendBall", "quick ball": "quickBall", "love ball": "loveBall",
}


def name_key(value):
    folded = unicodedata.normalize("NFKD", value.casefold().replace("&", " and "))
    return " ".join(re.findall(r"[a-z0-9]+", "".join(c for c in folded if not unicodedata.combining(c))))


def local_number(value):
    number = value.split("/", 1)[0].strip().lower()
    return str(int(number)) if re.fullmatch(r"[0-9]+", number) else number


def read_json(path):
    return json.loads(path.read_bytes())


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        temp = Path(stream.name)
        try:
            stream.write(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
            stream.close()
            temp.replace(path)
        finally:
            temp.unlink(missing_ok=True)


def checklist(root, set_id):
    snapshot = root / SNAPSHOT
    entries = [entry for entry in read_json(snapshot / "manifest.json")["entries"] if entry["providerID"] == set_id]
    if not entries:
        raise ValueError(f"Set {set_id} is absent from the bundled manifest")
    cards, sources = {}, {}
    for entry in entries:
        resource = entry["resource"]
        raw = (snapshot / resource).read_bytes()
        slots = json.loads(raw)
        if not slots or len(slots) != entry.get("expandedSlotCount", len(slots)):
            raise ValueError(f"Incomplete checklist resource {resource}")
        sources[resource] = digest(raw)
        for slot in slots:
            card_id, number = slot["providerID"], slot["collectorNumber"]
            if slot["setID"]["providerID"] != set_id or not card_id or not local_number(number):
                raise ValueError(f"Foreign or inconsistent checklist card {card_id}")
            card = cards.setdefault(card_id, {"number": number, "name": slot["name"], "checklist": set()})
            if card["name"] != slot["name"] or card["number"] != number:
                raise ValueError(f"Conflicting checklist identity for {card_id}")
            if variant := slot.get("masterSetVariant"):
                card["checklist"].add(variant["id"])
    for card in cards.values():
        card["checklist"] = sorted(card["checklist"])
    return cards, sources, entries[0]["set"]["name"]


def numbered_products(raw_products, raw_prices, group_id):
    lanes = defaultdict(list)
    for row in validate_response(raw_prices, 3, group_id, "prices"):
        lanes[row["productId"]].append(row["subTypeName"])
    products = defaultdict(list)
    for row in validate_response(raw_products, 3, group_id, "products"):
        numbers = {field["value"].strip() for field in row["extendedData"] if field["name"] == "Number"}
        if not numbers or numbers == {""}:
            continue
        if len(numbers) != 1 or not local_number(next(iter(numbers))):
            raise ValueError(f"Conflicting numbers on market product {row['productId']}")
        number = next(iter(numbers))
        product_id = row["productId"]
        products[local_number(number)].append({
            "productId": product_id, "name": row["name"], "number": number, "subtypes": sorted(lanes[product_id]),
        })
    return products


def signed_normal_reviews(root):
    source = read_json(root / "publisher/catalog-input.json")
    return {variant["providerCardID"] for item in source["sets"]
            for variant in item.get("additionalVariants", []) if variant.get("normalNeedsReview") is True}


def product_finishes(card, product):
    name = product["name"].removesuffix(" - " + product["number"])
    title, separator, qualifier = name.removesuffix(")").rpartition(" (") if name.endswith(")") else (name, "", "")
    pattern = PATTERNS.get(name_key(qualifier).removesuffix(" pattern")) if separator else None
    if name_key(title if pattern else name) != name_key(card["name"]) or not product["subtypes"]:
        return None
    finishes = set()
    for subtype in product["subtypes"]:
        key = name_key(subtype)
        finish = LANES.get(key) or PATTERNS.get(key.removesuffix(" pattern"))
        if finish is None or (pattern and finish not in ("holo", "reverse", pattern)):
            return None
        finishes.add(pattern or finish)
    return finishes


def compare(cards, minimums, products):
    by_number = defaultdict(list)
    for card_id, card in cards.items():
        by_number[local_number(card["number"])].append(card_id)
    results = {}
    for number, card_ids in by_number.items():
        matches = products.get(number, [])
        for card_id in card_ids:
            card = cards[card_id]
            minimum = minimums.get(card_id, {})
            required = sorted(set(card["checklist"]) | set(minimum.get("minimum", [])))
            lanes = [product_finishes(card, product) for product in matches]
            market = sorted(set().union(*(lane for lane in lanes if lane is not None)))
            normal_review = minimum.get("normalNeedsReview", False)
            agrees = (len(card_ids) == 1 and matches and None not in lanes and required == market
                      and not normal_review)
            results[card_id] = {**card, "minimum": minimum.get("minimum", []), "normalNeedsReview": normal_review,
                                "market": market, "products": matches,
                                "status": "agree" if agrees else "conflict" if matches else "unmatched"}
    for number in sorted(products.keys() - by_number.keys()):
        results[f"market:{number}"] = {"status": "unmatched", "products": products[number]}
    return results


def report(root, set_id, group_id, fetch=read_http):
    cards, sources, name = checklist(root, set_id)
    path = root / EVIDENCE / f"{set_id}.json"
    coverage = read_json(root / SNAPSHOT / "finish-coverage.json")
    if set_id in coverage["sets"] or (path.exists() and read_json(path)["resolutions"]):
        raise ValueError(f"Preserve the existing reviewed evidence at {path}")
    if group_id < 1:
        raise ValueError("A positive Pokémon TCGplayer group ID is required")
    group_url = f"https://tcgcsv.com/tcgplayer/3/{group_id}"
    urls = {resource: f"{group_url}/{resource}" for resource in ("products", "prices")}
    marker = fetch(MARKER, 1024).decode().strip()
    raw = {resource: fetch(url) for resource, url in urls.items()}
    if not marker or marker != fetch(MARKER, 1024).decode().strip():
        raise ValueError("TCGCSV changed builds during capture")
    products = numbered_products(raw["products"], raw["prices"], group_id)
    minimums = read_json(root / SNAPSHOT / "finish-minimums.json")
    comparison = compare(cards, minimums, products)
    for card_id in cards.keys() & signed_normal_reviews(root):
        comparison[card_id]["signedNormalNeedsReview"] = True
        if comparison[card_id]["status"] == "agree":
            comparison[card_id]["status"] = "conflict"
    result = {"schemaVersion": 1, "setID": set_id, "setName": name, "tcgplayerGroupID": group_id,
              "standard": STANDARD, "capturedAt": stamp(), "sourceBuild": marker, "checklistSources": sources,
              "marketSources": {key: {"url": urls[key], "sha256": digest(value)} for key, value in raw.items()},
              "cards": comparison, "resolutions": {}}
    write_json(path, result)
    return result


def cited(root, resolution):
    if not isinstance(resolution, dict):
        return False
    citation, reason = resolution.get("citation"), resolution.get("reason")
    if not isinstance(citation, str) or not citation.strip() or not isinstance(reason, str) or not reason.strip():
        return False
    citation = citation.strip()
    url = urlsplit(citation)
    if url.scheme in ("http", "https"):
        return bool(url.netloc)
    path = (root / citation).resolve()
    return path.is_relative_to(root.resolve()) and path.is_file()


def certify(root, set_id):
    cards, sources, _ = checklist(root, set_id)
    evidence_path = EVIDENCE / f"{set_id}.json"
    evidence = read_json(root / evidence_path)
    group_id = evidence["tcgplayerGroupID"]
    if (evidence["schemaVersion"] != 1 or evidence["setID"] != set_id
            or type(group_id) is not int or group_id < 1 or evidence["checklistSources"] != sources):
        raise ValueError("Evidence does not match the bundled set and checklist bytes")
    reviewed = evidence["cards"]
    resolutions = evidence["resolutions"]
    if set(cards) != {card_id for card_id in reviewed if not card_id.startswith("market:")}:
        raise ValueError("Evidence must include every checklist card")
    if resolutions.keys() - reviewed.keys():
        raise ValueError("A resolution references a card absent from the report")
    signed = sorted(cards.keys() & signed_normal_reviews(root))
    if signed:
        raise ValueError(f"Publisher input still marks Normal for review: {', '.join(signed[:12])}")
    coverage_path = root / SNAPSHOT / "finish-coverage.json"
    coverage = read_json(coverage_path)
    if coverage["schemaVersion"] != 1:
        raise ValueError("Unsupported finish coverage schema")
    minimums_path = root / SNAPSHOT / "finish-minimums.json"
    minimums = read_json(minimums_path)
    certified, pending = {}, []
    for card_id, item in reviewed.items():
        resolution = resolutions.get(card_id)
        if card_id.startswith("market:"):
            if not resolution or not cited(root, resolution) or resolution.get("exclude") is not True:
                pending.append(card_id)
            continue
        minimum = minimums.get(card_id, {})
        required = sorted(set(cards[card_id]["checklist"]) | set(minimum.get("minimum", [])))
        if resolution is not None and cited(root, resolution):
            finishes = resolution.get("finishes")
        elif (resolution is None and item["status"] == "agree" and item["market"] == required
              and not item["normalNeedsReview"] and not minimum.get("normalNeedsReview")):
            finishes = required
        else:
            finishes = None
        if (not isinstance(finishes, list) or not finishes
                or not all(isinstance(value, str) and value and value == value.strip() for value in finishes)
                or len(set(finishes)) != len(finishes)):
            pending.append(card_id)
        else:
            certified[card_id] = sorted(finishes)
    if pending:
        raise ValueError(f"{len(pending)} unresolved cards: {', '.join(pending[:12])}")
    new_set = {"tcgplayerGroupID": group_id, "evidence": evidence_path.as_posix(), "cards": certified}
    previous = coverage["sets"].get(set_id, {})
    reviewed_at = previous.get("reviewedAt") if all(previous.get(key) == value for key, value in new_set.items()) else None
    coverage["sets"][set_id] = {**new_set, "reviewedAt": reviewed_at or stamp()[:10]}
    certified_ids = {card_id for entry in coverage["sets"].values() for card_id in entry["cards"]}
    table = minimum_table(ledger(), certified_ids)
    write_json(coverage_path, coverage)
    write_json(minimums_path, table)
    return len(certified)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    report_parser = commands.add_parser("report")
    report_parser.add_argument("set_id")
    report_parser.add_argument("--group", required=True, type=int)
    commands.add_parser("certify").add_argument("set_id")
    args = parser.parse_args()
    try:
        if args.command == "report":
            evidence = report(ROOT, args.set_id, args.group)
            counts = {status: sum(card["status"] == status for card in evidence["cards"].values())
                      for status in ("agree", "conflict", "unmatched")}
            print(f"{args.set_id}: {counts}")
        else:
            count = certify(ROOT, args.set_id)
            print(f"{args.set_id}: certified {count} numbered cards")
    except (KeyError, OSError, TypeError, ValueError, URLError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
