#!/usr/bin/env python3
"""Compare one bundled Pokémon set with TCGCSV, then certify a reviewed report.

Edit only the resolutions map in the capture's report.json. A card resolution
lists finishes, citation and reason. Flagged historical Normal requires a
normalReview decision of include or exclude. Each omitted ledger finish needs
a supersedes entry with source (finish-minimums or legacy-finish-evidence),
finish, citation and reason. Resolve a foreign market product with exclude,
citation and reason.

Clear signed Normal review in publisher input before capture. To refresh
evidence, run report with a new --revision name, review the earlier decisions
against the new comparison, and certify that revision with the same flag.
Each capture keeps its own checklist and market bytes, receipt and review.
Replay accepts these directories and older flat reports with a retained
market cache. Use --legacy-snapshot with the matching archived bundle when
the current checklist has changed since a flat report was captured.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
from pathlib import Path
import re
import tempfile
import unicodedata
from urllib.error import URLError
from urllib.parse import urlsplit

from audit_pokemon_finish_repairs import ROOT, ledger, minimum_table
from market_price_feeds import digest, packed, read_http, stamp, validate_response

SNAPSHOT = Path("TradingCardScanner/PokemonChecklistSnapshot")
EVIDENCE = Path("docs/research/pokemon-finish-coverage")
CAPTURES = EVIDENCE / "captures"
MARKER = "https://tcgcsv.com/last-updated.txt"
REPORT_VERSION = 2
FIRST_REVISION = "initial"
STANDARD = (
    "Each numbered checklist card must agree with the matching TCGplayer products on exact finishes, "
    "or have a cited resolution. Every conflict, unmatched number and Normal review must be resolved. "
    "Market listings are evidence of membership. Physical or retail evidence resolves disagreements."
)
LANES = {"normal": "normal", "holofoil": "holo", "reverse holofoil": "reverse"}
PATTERNS = {
    "poke ball": "pokeBall", "master ball": "masterBall", "dusk ball": "duskBall",
    "friend ball": "friendBall", "quick ball": "quickBall", "love ball": "loveBall",
    "energy symbol": "energy", "team rocket": "team-rocket",
}
TRAINER_CHARACTER_LABELS = {
    "boss s orders": {"corbeau", "ghetsis"},
    "professor s research": {
        "professor elm", "professor juniper", "professor oak", "professor rowan",
        "professor sada", "professor sycamore", "professor turo",
    },
}
MARKET_ENERGY_INITIALS = {"grass": "g", "water": "w", "fire": "r"}


def name_key(value):
    value = value.casefold().replace("&", " and ").replace("♀", " female").replace("♂", " male")
    folded = unicodedata.normalize("NFKD", value)
    return " ".join(re.findall(r"[a-z0-9]+", "".join(c for c in folded if not unicodedata.combining(c))))


def local_number(value):
    number = value.split("/", 1)[0].strip().lower()
    return str(int(number)) if re.fullmatch(r"[0-9]+", number) else number


def without_number_suffix(name, number):
    title, separator, suffix = name.rpartition(" - ")
    # Preserve the denominator. Equal numerators alone can name different products.
    if separator and [local_number(part) for part in suffix.split("/")] == [
        local_number(part) for part in number.split("/")
    ]:
        return title
    match = re.fullmatch(
        r"(.+) \((\d+[a-z]?)(?: Secret Rare| Full Art(?: Secret Rare)?| Secret Full Art)?\)",
        name, re.IGNORECASE,
    )
    if match and local_number(match[2]) == local_number(number):
        return match[1]
    return name


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


def checklist(root, set_id, *, read_bytes=Path.read_bytes, aggregate_evidence=None, snapshot=None):
    snapshot = snapshot or root / SNAPSHOT
    manifest = json.loads(read_bytes(snapshot / "manifest.json"))
    entries = [entry for entry in manifest["entries"] if entry["providerID"] == set_id]
    if not entries:
        raise ValueError(f"Set {set_id} is absent from the bundled manifest")
    cards, sources = {}, {}
    for entry in entries:
        resource = entry["resource"]
        if Path(resource).is_absolute() or ".." in Path(resource).parts or resource == "manifest.json":
            raise ValueError(f"Unsafe checklist resource {resource}")
        raw = read_bytes(snapshot / resource)
        slots = json.loads(raw)
        if not slots or len(slots) != entry.get("expandedSlotCount", len(slots)):
            raise ValueError(f"Incomplete checklist resource {resource}")
        sources[resource] = digest(raw)
        variants_by_card = defaultdict(set)
        for slot in slots:
            card_id, number = slot["providerID"], slot["collectorNumber"]
            if slot["setID"]["providerID"] != set_id or not card_id or not local_number(number):
                raise ValueError(f"Foreign or inconsistent checklist card {card_id}")
            card = cards.setdefault(card_id, {"number": number, "name": slot["name"], "checklist": set()})
            if card["name"] != slot["name"] or card["number"] != number:
                raise ValueError(f"Conflicting checklist identity for {card_id}")
            if variant := slot.get("masterSetVariant"):
                variants_by_card[card_id].add(variant["id"])
        evidence = aggregate_evidence or {}
        if evidence.get("aggregateChecklistSources", {}).get(resource) == sources[resource]:
            holo = evidence["holoAggregates"]
            reverse = evidence["reverseAggregates"]
            for card_id, variants in variants_by_card.items():
                if card_id in holo and variants.intersection(holo[card_id]):
                    variants.discard("holo")
                if card_id in reverse and variants.issuperset(reverse[card_id]):
                    variants.discard("reverse")
        for card_id, variants in variants_by_card.items():
            cards[card_id]["checklist"].update(variants)
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


def signed_finish_evidence(root, set_id, cards):
    # Match the app's signed catalog identity, which folds punctuation to
    # spaces. Market title matching has separate rules for product qualifiers.
    def catalog_name(value):
        folded = unicodedata.normalize("NFD", value.casefold().replace("&", " and "))
        return " ".join("".join(c if c.isalnum() else " " for c in folded if not unicodedata.combining(c)).split())

    source = read_json(root / "publisher/catalog-input.json")
    matched = defaultdict(list)
    for item in source["sets"]:
        if item["providerSetID"] != set_id:
            continue
        for variant in item.get("additionalVariants", []):
            card_id = variant["providerCardID"]
            if (card := cards.get(card_id)) and catalog_name(variant["canonicalName"]) == catalog_name(card["name"]):
                matched[card_id].append(variant)
    return dict(matched)


def signed_standard_finishes(variants):
    return {
        variant_id for variant in variants
        if (variant_id := variant.get("variantID")) and variant_id != "jumbo"
        and not variant.get("excludedTCGplayerProductIDs")
    }


@dataclass(frozen=True)
class FinishEvidence:
    minimums: dict
    historical: dict
    signed: dict
    vocabulary: set
    sha256: str

    def require_signed_review_closed(self):
        open_reviews = sorted(
            card_id for card_id, variants in self.signed.items()
            if any(variant.get("normalNeedsReview") is True for variant in variants)
        )
        if open_reviews:
            raise ValueError(f"Publisher input still marks Normal for review: {', '.join(open_reviews[:12])}")


def current_inputs(root, set_id, audited_minimums, *, snapshot=None):
    legacy_raw = (root / SNAPSHOT / "legacy-finish-evidence.json").read_bytes()
    legacy = json.loads(legacy_raw)
    if legacy["schemaVersion"] != 1:
        raise ValueError("Unsupported historical finish evidence schema")
    cards, sources, name = checklist(root, set_id, aggregate_evidence=legacy, snapshot=snapshot)

    def applicable(rows):
        return {card_id: row for card_id, row in rows.items() if card_id in cards
                and row["setID"] == set_id and card_id == f"{set_id}-{row['number']}"}

    minimums = applicable(audited_minimums)
    historical = applicable(legacy["cards"])
    signed = signed_finish_evidence(root, set_id, cards)
    vocabulary_raw = (root / SNAPSHOT / "finish-coverage-variants.json").read_bytes()
    vocabulary = json.loads(vocabulary_raw)
    if (not isinstance(vocabulary, list) or not all(isinstance(value, str) and value for value in vocabulary)
            or "jumbo" in vocabulary or "firstEdition" in vocabulary):
        raise ValueError("Invalid standard Pokémon finish vocabulary")
    evidence_hash = digest(packed({
        "legacySHA256": digest(legacy_raw),
        "minimums": minimums,
        "signed": signed,
        "vocabularySHA256": digest(vocabulary_raw),
    }))
    return cards, sources, name, FinishEvidence(minimums, historical, signed, set(vocabulary), evidence_hash)


def require_audited_minimum_projection(root, cards, evidence, *, already_certified):
    generated = read_json(root / SNAPSHOT / "finish-minimums.json")
    applicable = {card_id: generated[card_id] for card_id in cards.keys() & generated.keys()}
    # A completed certificate retires these rows. A retry can also repair a
    # partial write that published coverage before retiring the minimums.
    if (any(evidence.minimums.get(card_id) != row for card_id, row in applicable.items())
            or (not already_certified and applicable != evidence.minimums)):
        raise ValueError("Bundled finish minimums differ from the audited source. Regenerate finish-minimums.json.")


def product_finishes(card, product):
    if local_number(card["number"]) != local_number(product["number"]):
        return None
    name = without_number_suffix(product["name"], product["number"])
    title, separator, qualifier = name.removesuffix(")").rpartition(" (") if name.endswith(")") else (name, "", "")
    pattern = PATTERNS.get(name_key(qualifier).removesuffix(" pattern")) if separator else None
    if pattern:
        name = without_number_suffix(title, product["number"])
    expected_name = name_key(card["name"])
    if separator and name_key(qualifier) in {
        "full art", "alternate full art", "shiny full art", "secret", "secret rare",
    }:
        name = without_number_suffix(title, product["number"])
    elif separator and name_key(qualifier) == "basic" and expected_name.endswith(" energy"):
        name = without_number_suffix(title, product["number"])
    elif separator and name_key(qualifier) in {"left", "right"} and expected_name.startswith("legendary "):
        name = without_number_suffix(title, product["number"])
    if name.endswith("]"):
        title, separator, character = name.removesuffix("]").rpartition(" [")
        if separator and name_key(character) in TRAINER_CHARACTER_LABELS.get(expected_name, ()):
            name = title
    expected_names = {expected_name}
    words = expected_name.rsplit(" ", 2)
    if len(words) == 3 and words[2] == "energy" and words[1] in MARKET_ENERGY_INITIALS:
        expected_names.add(f"{words[0]} {MARKET_ENERGY_INITIALS[words[1]]} energy")
    if name_key(name) not in expected_names or not product["subtypes"]:
        return None
    finishes = set()
    for subtype in product["subtypes"]:
        key = name_key(subtype)
        finish = LANES.get(key) or PATTERNS.get(key.removesuffix(" pattern"))
        if finish is None or (pattern and finish not in ("holo", "reverse", pattern)):
            return None
        finishes.add(pattern or finish)
    return finishes


def compare(cards, minimums, products, *, historical=None, signed=None):
    historical = historical or {}
    signed = signed or {}
    by_number = defaultdict(list)
    for card_id, card in cards.items():
        by_number[local_number(card["number"])].append(card_id)
    results = {}
    for number, card_ids in by_number.items():
        numbered = products.get(number, [])
        matched = defaultdict(list)
        for product in numbered:
            candidates = [
                (card_id, finishes) for card_id in card_ids
                if (finishes := product_finishes(cards[card_id], product)) is not None
            ]
            if len(candidates) == 1:
                card_id, finishes = candidates[0]
                matched[card_id].append((product, finishes))
            else:
                results[f"market:product:{product['productId']}"] = {
                    "status": "unmatched", "products": [product],
                    "checklistIdentitiesAtNumber": card_ids,
                }
        for card_id in card_ids:
            card = cards[card_id]
            minimum = minimums.get(card_id, {})
            legacy = historical.get(card_id, {})
            signed_rows = signed.get(card_id, [])
            signed_finishes = signed_standard_finishes(signed_rows)
            signed_review = any(variant.get("normalNeedsReview") is True for variant in signed_rows)
            checklist_finishes = set(card["checklist"])
            if legacy.get("normalNeedsReview"):
                checklist_finishes.discard("normal")
            required = sorted(checklist_finishes | set(minimum.get("minimum", []))
                              | set(legacy.get("minimum", [])) | signed_finishes)
            matches = matched[card_id]
            market = sorted({finish for _, finishes in matches for finish in finishes})
            normal_review = bool(minimum.get("normalNeedsReview") or legacy.get("normalNeedsReview"))
            agrees = bool(matches) and required == market and not normal_review and not signed_review
            row = {**card, "minimum": minimum.get("minimum", []), "normalNeedsReview": normal_review,
                   "required": required, "market": market, "products": [product for product, _ in matches],
                   "status": "agree" if agrees else "conflict" if numbered else "unmatched"}
            if legacy:
                row["legacyMinimum"] = legacy["minimum"]
            if signed_finishes:
                row["signedStandardFinishes"] = sorted(signed_finishes)
            if signed_review:
                row["signedNormalNeedsReview"] = True
            results[card_id] = row
    for number in sorted(products.keys() - by_number.keys()):
        results[f"market:{number}"] = {"status": "unmatched", "products": products[number]}
    return results


def compare_current(cards, products, evidence):
    return compare(cards, evidence.minimums, products, historical=evidence.historical, signed=evidence.signed)


def capture_directory(root, set_id, revision):
    for value in (set_id, revision):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", value):
            raise ValueError(f"Invalid set or capture revision: {value!r}")
    return root / CAPTURES / set_id / revision


def verify_receipt(path, report):
    if not path.is_file():
        raise ValueError("Missing captured comparison receipt; generate a bound report before certifying")
    comparison = {key: value for key, value in report.items() if key != "resolutions"}
    if read_json(path)["comparisonSHA256"] != digest(packed(comparison)):
        raise ValueError("Report differs from the captured comparison; edit only resolutions")


def retained_market(report, directory, *, versioned):
    if directory is None:
        raise ValueError("Legacy reports require --market-cache with the retained products and prices")
    group = report["tcgplayerGroupID"]
    raw = {}
    for resource in ("products", "prices"):
        filename = f"{resource}.json" if versioned else f"{group}-{resource}.json"
        raw[resource] = (directory / filename).read_bytes()
        expected = {"url": f"https://tcgcsv.com/tcgplayer/3/{group}/{resource}", "sha256": digest(raw[resource])}
        if report["marketSources"][resource] != expected:
            raise ValueError(f"Market {resource} bytes differ from capture for {report['setID']}")
    return numbered_products(raw["products"], raw["prices"], group)


def replay(root, report_dir, market_dir=None, *, legacy_snapshot=None):
    output = {"schemaVersion": 1, "sets": {}}
    audited_minimums = minimum_table(ledger(), set())
    single_report = report_dir / "report.json"
    paths = {single_report} if single_report.is_file() else {
        path for pattern in ("*.json", "*/report.json", "*/*/report.json", "captures/*/*/report.json")
        for path in report_dir.glob(pattern)
    }
    for path in sorted(paths):
        original = read_json(path)
        set_id = original["setID"]
        group = original["tcgplayerGroupID"]
        revision = original.get("captureRevision")
        versioned = original["schemaVersion"] == REPORT_VERSION
        valid_identity = (path.name == "report.json" and path.parent.name == revision
                          and path.parent.parent.name == set_id) if versioned else path.stem == set_id
        if original["schemaVersion"] not in (1, REPORT_VERSION) or not valid_identity or type(group) is not int or group < 1:
            raise ValueError(f"Invalid report identity for {path.name}")
        if versioned:
            verify_receipt(path.with_name("receipt.json"), original)
        cards, sources, _, evidence = current_inputs(root, set_id, audited_minimums,
            snapshot=path.parent / "checklist" if versioned else legacy_snapshot)
        if original["checklistSources"] != sources:
            raise ValueError(f"Bundled checklist bytes differ from capture for {set_id}")
        products = retained_market(original, path.parent if versioned else market_dir, versioned=versioned)
        comparison = compare_current(cards, products, evidence)
        previous = original["cards"]
        if set(cards) != {card_id for card_id in previous if not card_id.startswith("market:")}:
            raise ValueError(f"Archived comparison does not cover the checklist for {set_id}")
        key = f"{set_id}@{revision}" if versioned else set_id
        output["sets"][key] = {
            "checklistSources": sources, "marketSources": original["marketSources"],
            "finishEvidenceSHA256": evidence.sha256,
            "cardRows": {
                card_id: {"baseline": previous[card_id]["status"], "replay": comparison[card_id]}
                for card_id in cards
            },
            "marketRows": {key: row for key, row in comparison.items() if key.startswith("market:")},
        }
    if not output["sets"]:
        raise ValueError("No retained finish comparisons found")
    return output


def report(root, set_id, group_id, fetch=read_http, *, revision=None):
    capture = capture_directory(root, set_id, revision if revision is not None else FIRST_REVISION)
    coverage = read_json(root / SNAPSHOT / "finish-coverage.json")
    legacy = root / EVIDENCE / f"{set_id}.json"
    if capture.exists() or (revision is None and (legacy.exists() or set_id in coverage["sets"])):
        raise ValueError("Preserve the existing capture and choose a new --revision")
    if type(group_id) is not int or group_id < 1:
        raise ValueError("A positive Pokémon TCGplayer group ID is required")
    cards, sources, name, evidence = current_inputs(root, set_id, minimum_table(ledger(), set()))
    evidence.require_signed_review_closed()
    require_audited_minimum_projection(root, cards, evidence, already_certified=set_id in coverage["sets"])
    group_url = f"https://tcgcsv.com/tcgplayer/3/{group_id}"
    urls = {resource: f"{group_url}/{resource}" for resource in ("products", "prices")}
    marker = fetch(MARKER, 1024).decode().strip()
    raw = {resource: fetch(url) for resource, url in urls.items()}
    if not marker or marker != fetch(MARKER, 1024).decode().strip():
        raise ValueError("TCGCSV changed builds during capture")
    products = numbered_products(raw["products"], raw["prices"], group_id)
    comparison = compare_current(cards, products, evidence)
    result = {"schemaVersion": REPORT_VERSION, "captureRevision": capture.name,
              "setID": set_id, "setName": name, "tcgplayerGroupID": group_id,
              "standard": STANDARD, "capturedAt": stamp(), "sourceBuild": marker, "checklistSources": sources,
              "finishEvidenceSHA256": evidence.sha256,
              "marketSources": {key: {"url": urls[key], "sha256": digest(value)} for key, value in raw.items()},
              "cards": comparison}
    receipt = {"comparisonSHA256": digest(packed(result))}
    report_value = {**result, "resolutions": {}}
    capture.parent.mkdir(parents=True, exist_ok=True)
    # Publish all files together. Concurrent recaptures of the same revision
    # cannot replace a populated directory.
    with tempfile.TemporaryDirectory(prefix=".capture-", dir=capture.parent) as temp:
        stage = Path(temp) / "capture"
        archived = stage / "checklist"
        for resource in ("manifest.json", *sources):
            dest = archived / resource
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes((root / SNAPSHOT / resource).read_bytes())
        _, archived_sources, _ = checklist(root, set_id, snapshot=archived)
        if archived_sources != sources:
            raise ValueError("Bundled checklist changed during capture")
        for resource, data in raw.items():
            (stage / f"{resource}.json").write_bytes(data)
        write_json(stage / "receipt.json", receipt)
        write_json(stage / "report.json", report_value)
        stage.rename(capture)
    return report_value


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


def require_ledger_supersession(root, card_id, finishes, resolution, evidence):
    omitted = {
        (source, finish)
        for source, entries in (("finish-minimums", evidence.minimums), ("legacy-finish-evidence", evidence.historical))
        for finish in entries.get(card_id, {}).get("minimum", [])
        if finish not in finishes
    }
    supersedes = resolution.get("supersedes", []) if resolution is not None else []
    if not isinstance(supersedes, list):
        raise ValueError(f"{card_id} needs a list of superseded ledger finishes")
    for item in supersedes:
        if (not cited(root, item) or not isinstance(item.get("source"), str)
                or not isinstance(item.get("finish"), str)
                or (item["source"], item["finish"]) not in omitted):
            raise ValueError(f"{card_id} has a supersession without matching omitted evidence and citation")
        omitted.remove((item["source"], item["finish"]))
    if omitted:
        details = ", ".join(f"{source}/{finish}" for source, finish in sorted(omitted))
        raise ValueError(f"{card_id} omits reviewed ledger finishes without supersession: {details}")


def certify(root, set_id, *, revision=FIRST_REVISION):
    capture = capture_directory(root, set_id, revision)
    report_path = capture / "report.json"
    if not report_path.is_file():
        raise ValueError("Generate a bound report with report --revision before certifying this capture")
    report_value = read_json(report_path)
    group_id = report_value["tcgplayerGroupID"]
    if (report_value["schemaVersion"] != REPORT_VERSION or report_value["setID"] != set_id
            or report_value.get("captureRevision") != revision or type(group_id) is not int or group_id < 1):
        raise ValueError("Evidence does not identify this capture revision")
    verify_receipt(capture / "receipt.json", report_value)
    audited = ledger()
    cards, sources, _, evidence = current_inputs(root, set_id, minimum_table(audited, set()))
    if report_value["checklistSources"] != sources:
        raise ValueError("Evidence does not match the bundled set and checklist bytes")
    if report_value.get("finishEvidenceSHA256") != evidence.sha256:
        raise ValueError("Finish evidence changed. Capture a new --revision and review its comparison.")
    evidence.require_signed_review_closed()
    _, archived_sources, _ = checklist(root, set_id, snapshot=capture / "checklist")
    if archived_sources != sources:
        raise ValueError("Retained checklist bytes differ from the capture")
    products = retained_market(report_value, capture, versioned=True)
    reviewed = report_value["cards"]
    resolutions = report_value["resolutions"]
    if set(cards) != {card_id for card_id in reviewed if not card_id.startswith("market:")}:
        raise ValueError("Evidence must include every checklist card")
    if resolutions.keys() - reviewed.keys():
        raise ValueError("A resolution references a card absent from the report")
    if reviewed != compare_current(cards, products, evidence):
        raise ValueError("Comparison rules changed. Capture a new --revision and review its comparison.")
    coverage_path = root / SNAPSHOT / "finish-coverage.json"
    coverage = read_json(coverage_path)
    if coverage["schemaVersion"] != 1:
        raise ValueError("Unsupported finish coverage schema")
    require_audited_minimum_projection(root, cards, evidence, already_certified=set_id in coverage["sets"])
    minimums_path = root / SNAPSHOT / "finish-minimums.json"
    certified, pending = {}, []
    for card_id, item in reviewed.items():
        resolution = resolutions.get(card_id)
        if card_id.startswith("market:"):
            if not resolution or not cited(root, resolution) or resolution.get("exclude") is not True:
                pending.append(card_id)
            continue
        required = item["required"]
        if resolution is not None and cited(root, resolution):
            finishes = resolution.get("finishes")
        elif (resolution is None and item["status"] == "agree" and item["market"] == required
              and not item["normalNeedsReview"]):
            finishes = required
        else:
            finishes = None
        if (not isinstance(finishes, list) or not finishes
                or not all(isinstance(value, str) and value and value == value.strip() for value in finishes)
                or len(set(finishes)) != len(finishes)):
            pending.append(card_id)
            continue
        finish_ids = set(finishes)
        if unsupported := finish_ids - evidence.vocabulary:
            raise ValueError(f"{card_id} has unsupported standard Pokémon finishes: {', '.join(sorted(unsupported))}")
        if omitted := signed_standard_finishes(evidence.signed.get(card_id, [])) - finish_ids:
            raise ValueError(f"{card_id} omits signed standard finishes: {', '.join(sorted(omitted))}")
        if item["normalNeedsReview"]:
            decision = "include" if "normal" in finish_ids else "exclude"
            if resolution is None or resolution.get("normalReview") != decision:
                raise ValueError(f"{card_id} needs a cited Normal review decision of {decision}")
        require_ledger_supersession(root, card_id, finish_ids, resolution, evidence)
        certified[card_id] = sorted(finishes)
    if pending:
        raise ValueError(f"{len(pending)} unresolved cards: {', '.join(pending[:12])}")
    new_set = {"tcgplayerGroupID": group_id, "evidence": report_path.relative_to(root).as_posix(), "cards": certified}
    previous = coverage["sets"].get(set_id, {})
    reviewed_at = previous.get("reviewedAt") if all(previous.get(key) == value for key, value in new_set.items()) else None
    coverage["sets"][set_id] = {**new_set, "reviewedAt": reviewed_at or stamp()[:10]}
    certified_ids = {card_id for entry in coverage["sets"].values() for card_id in entry["cards"]}
    table = minimum_table(audited, certified_ids)
    write_json(coverage_path, coverage)
    write_json(minimums_path, table)
    return len(certified)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    report_parser = commands.add_parser("report")
    report_parser.add_argument("set_id")
    report_parser.add_argument("--group", required=True, type=int)
    report_parser.add_argument("--revision", help="Name for a new capture directory")
    replay_parser = commands.add_parser("replay")
    replay_parser.add_argument("--reports", required=True, type=Path)
    replay_parser.add_argument("--market-cache", type=Path, help="Retained market files for legacy reports")
    replay_parser.add_argument("--legacy-snapshot", type=Path, help="Matching archived checklist bundle for legacy reports")
    replay_parser.add_argument("--output", required=True, type=Path)
    certify_parser = commands.add_parser("certify")
    certify_parser.add_argument("set_id")
    certify_parser.add_argument("--revision", default=FIRST_REVISION)
    args = parser.parse_args()
    try:
        if args.command == "report":
            evidence = report(ROOT, args.set_id, args.group, revision=args.revision)
            counts = {status: sum(card["status"] == status for card in evidence["cards"].values())
                      for status in ("agree", "conflict", "unmatched")}
            print(f"{args.set_id}: {counts}")
            print(capture_directory(ROOT, args.set_id, evidence["captureRevision"]) / "report.json")
        elif args.command == "replay":
            result = replay(ROOT, args.reports, args.market_cache, legacy_snapshot=args.legacy_snapshot)
            write_json(args.output, result)
            print(f"Replayed {len(result['sets'])} retained finish comparisons")
        else:
            count = certify(ROOT, args.set_id, revision=args.revision)
            print(f"{args.set_id}: certified {count} numbered cards")
    except (KeyError, OSError, TypeError, ValueError, URLError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
