#!/usr/bin/env python3
"""Derive minimum finish evidence for bundled Normal-only Pokémon sets.

Inputs are retained English TCGdex set responses, a pinned Pokémon TCG Data
card list, and retained TCGCSV product and price captures. Aggregate repairs also need
the original checklist snapshot used to review the Holo and Reverse slots.
The sources establish exact card identity and positive market membership.
A missing lane is a review question. This output never certifies exhaustive
finish coverage.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

from certify_pokemon_finish_coverage import (
    ROOT, SNAPSHOT, LANES, checklist, compare, local_number, name_key, numbered_products,
    product_finishes, read_json, without_number_suffix, write_json,
)
from market_price_feeds import digest, validate_response

REVIEWED_SETS = {"sma", "xya"}  # Already covered by dedicated physical evidence.
STANDARD = {"normal", "holo", "reverse"}
TRAIT_NAMES = {"Ω": "Omega", "α": "Alpha", "Δ": "Delta"}
FAIRY_CHARM_MARKET_TYPES = {"Grass": "G", "Psychic": "P", "Fighting": "F", "Dragon": "O"}
ALTERNATE_ART_MARKET_GROUP = 1938
LINKED_PRICE_LANES = {
    "normal": "Normal", "holofoil": "Holofoil", "holo": "Holofoil",
    "reverse-holofoil": "Reverse Holofoil", "reverse": "Reverse Holofoil",
}
ASCENDED_REVERSE_PATTERNS = {
    "pokeball": "pokeBall", "duskball": "duskBall", "friendball": "friendBall",
    "quickball": "quickBall", "loveball": "loveBall", "team-rocket": "team-rocket", "energy": "energy",
}


def capture_files(evidence, receipt):
    files = {}
    for item in receipt["files"]:
        relative = Path(item["file"])
        path = (evidence / relative).resolve()
        if relative in files or not path.is_relative_to(evidence.resolve()):
            raise ValueError(f"Unsafe or duplicate capture path {relative}")
        files[relative] = item
    return files


def captured(evidence, files, relative, url):
    item = files[Path(relative)]
    raw = (evidence / relative).read_bytes()
    if item["url"] != url or digest(raw) != item["sha256"]:
        raise ValueError(f"Capture identity or bytes changed for {relative}")
    return raw


def special_energy_identity(name):
    for family, count in (("Blend Energy", 4), ("Unit Energy", 3)):
        if not name.startswith(family + " "):
            continue
        suffix = name.removeprefix(family + " ").replace(" ", "")
        types = re.findall(r"Grass|Fire|Water|Lightning|Psychic|Fighting|Darkness|Metal|Fairy|Dragon", suffix)
        if len(types) == count and "".join(types) == suffix:
            return family, types
    return None


def identity_agrees(card, alternate, number_key):
    if alternate is None or local_number(card["number"]) != local_number(str(alternate[number_key])):
        return False
    if name_key(card["name"]) == name_key(alternate["name"]):
        return True
    if alternate.get("supertype") == "Energy" and "Special" in alternate.get("subtypes", []):
        identity = special_energy_identity(card["name"])
        return identity is not None and identity == special_energy_identity(alternate["name"])
    return False


def unique_cards(rows):
    cards = {row["id"]: row for row in rows}
    if len(cards) != len(rows):
        raise ValueError("A retained card list contains duplicate IDs")
    return cards


def product_name(product, independent, card_name):
    name = product["name"]
    subtypes = independent.get("subtypes", [])
    if "Team Plasma" in subtypes:
        name = re.sub(r" \(Team Plasma\)(?= \(| - |$)", "", name, flags=re.IGNORECASE)
    if "Supporter" in subtypes:
        name = re.sub(r" \(Supporter\)(?= \(| - |$)", "", name, flags=re.IGNORECASE)
    if "Prism Star" in subtypes and independent["name"].endswith("◇"):
        name = re.sub(r" Prism Star(?= \(| - |$)", " ◇", name, flags=re.IGNORECASE)
    mega_form = re.fullmatch(r"M Charizard[- ]EX \(([XY])\)( \(Secret\))?", name, flags=re.IGNORECASE)
    if mega_form and {"MEGA", "EX"}.issubset(subtypes) and name_key(independent["name"]) == "m charizard ex":
        form_attack = {"X": "Wild Blaze", "Y": "Crimson Dive"}[mega_form[1].upper()]
        secret = independent.get("rarity") == "Rare Secret"
        if secret == bool(mega_form[2]) and any(
            attack.get("name") == form_attack for attack in independent.get("attacks", [])
        ):
            name = independent["name"]
    alias = None
    if independent.get("supertype") == "Energy" and "Special" in subtypes:
        if identity := special_energy_identity(independent["name"]):
            family, types = identity
            code = "".join("R" if family == "Unit Energy" and energy_type == "Fire" else energy_type[0]
                           for energy_type in types)
            alias = family + " " + code
    elif "Pokémon Tool" in subtypes and independent["name"].startswith("Fairy Charm "):
        if code := FAIRY_CHARM_MARKET_TYPES.get(independent["name"].removeprefix("Fairy Charm ")):
            alias = "Fairy Charm " + code
    if alias:
        name = re.sub(rf"^{re.escape(alias)}(?= \(| - |$)", card_name, name, flags=re.IGNORECASE)
    for annotation in (" Team Flare Gear", " Team Flare Hyper Gear"):
        if independent["name"].endswith(annotation):
            title = independent["name"].removesuffix(annotation)
            if name_key(without_number_suffix(name, product["number"])) == name_key(title):
                name = independent["name"]
    trait = TRAIT_NAMES.get((independent.get("ancientTrait") or {}).get("name", "")[:1])
    if trait:
        name = re.sub(rf" \({trait}\)(?= \(| - |$)", "", name, flags=re.IGNORECASE)
        name = re.sub(rf" \({trait} - (?=\d)", " (", name, flags=re.IGNORECASE)
        name = re.sub(rf"(?<=\d) {trait}\)$", ")", name, flags=re.IGNORECASE)
    for symbol, suffix in (("♀", "F"), ("♂", "M")):
        if symbol in independent["name"]:
            name = re.sub(rf"^Nidoran (?:{suffix}|\({suffix}\))(?= \(| - |$)",
                          f"Nidoran{symbol}", name, flags=re.IGNORECASE)
    return name


def match_cards(cards, primary, secondary, products):
    by_identity = defaultdict(list)
    for card_id, card in cards.items():
        by_identity[local_number(card["number"]), name_key(card["name"])].append(card_id)

    result = {}
    for card_id, card in cards.items():
        number = local_number(card["number"])
        matches = []
        status = "matched"
        independent = secondary.get(card_id)
        if len(by_identity[number, name_key(card["name"])]) != 1:
            status = "ambiguous checklist identity"
        elif not identity_agrees(card, primary.get(card_id), "localId"):
            status = "TCGdex identity differs"
        elif not identity_agrees(card, independent, "number"):
            status = "independent catalog identity unavailable or differs"
        else:
            for product in products.get(number, []):
                title = product_name(product, independent, card["name"])
                variants = product_finishes(card, dict(product, name=title))
                if variants and variants <= STANDARD:
                    matches.append((product["productId"], variants))
            if not matches:
                status = "exact standard market product unavailable"

        finishes = sorted({finish for _, variants in matches for finish in variants})
        unmatched = sorted(
            product["productId"] for product in products.get(number, [])
            if product["productId"] not in {product_id for product_id, _ in matches}
        )
        result[card_id] = {
            "name": card["name"], "number": card["number"],
            "minimum": finishes, "status": status,
            "productIDs": sorted(product_id for product_id, _ in matches),
            "otherProductsAtNumber": unmatched,
        }
    return result


def alternate_market_products(evidence, entries, by_set):
    review = read_json(evidence / "verified-alternates.json")
    group = review["marketGroup"]
    if group != ALTERNATE_ART_MARKET_GROUP:
        raise ValueError("Unexpected alternate-art market group")
    start = (evidence / "start.txt").read_bytes()
    if start != (evidence / "end.txt").read_bytes() or start.decode().strip() != review["marketBuild"]:
        raise ValueError("Alternate-art market capture crossed source builds")
    raw = {kind: (evidence / f"{group}-{kind}.json").read_bytes() for kind in ("products", "prices")}
    for kind, data in raw.items():
        expected = {"url": f"https://tcgcsv.com/tcgplayer/3/{group}/{kind}", "sha256": digest(data)}
        if review["marketSources"].get(kind) != expected:
            raise ValueError(f"Alternate-art market {kind} differs from the retained receipt")

    footers = defaultdict(set)
    for entry in entries:
        count = entry.get("officialCount")
        if not count:
            continue
        for slot in by_set[entry["providerID"]]:
            number = local_number(slot["collectorNumber"])
            if re.fullmatch(r"[0-9]+[a-z]+", number):
                footers[number, str(count)].add(slot["providerID"])

    by_card = defaultdict(list)
    for number, products in numbered_products(raw["products"], raw["prices"], group).items():
        for product in products:
            denominator = product["number"].partition("/")[2].strip()
            if not re.fullmatch(r"[0-9]+", denominator):
                continue
            ids = footers.get((number, local_number(denominator)), set())
            if len(ids) == 1:
                by_card[next(iter(ids))].append(product)
    return by_card, {key: review[key] for key in ("marketGroup", "marketBuild", "marketSources")}


def apply_unnumbered_energy(matches, cards, primary, secondary, raw_products, raw_prices, group):
    products = defaultdict(list)
    for product in validate_response(raw_products, 3, group, "products"):
        if product["name"].endswith(" (2017 Unnumbered)") and not any(
            field["name"] == "Number" and field["value"].strip() for field in product["extendedData"]
        ):
            products[product["name"].removesuffix(" (2017 Unnumbered)")].append(product)
    lanes = defaultdict(set)
    for price in validate_response(raw_prices, 3, group, "prices"):
        lanes[price["productId"]].add(LANES.get(name_key(price["subTypeName"])))

    # These are the unnumbered 2017 designs included alongside the set. The
    # provider's nine numeric IDs are stable keys, never printed numbers.
    for number in range(164, 173):
        card_id = f"sm1-{number}"
        card = cards.get(card_id)
        independent = secondary.get(card_id)
        if (not card or not independent or independent.get("supertype") != "Energy"
                or "Basic" not in independent.get("subtypes", [])
                or not identity_agrees(card, primary.get(card_id), "localId")
                or not identity_agrees(card, independent, "number")):
            continue
        row = matches[card_id]
        row.update(isUnnumbered=True, minimum=[], status="exact unnumbered market product unavailable", productIDs=[])
        exact = [product for product in products[card["name"]] if any(
            field["name"] == "Card Type" and field["value"] == "Basic " + card["name"]
            for field in product["extendedData"]
        )]
        if len(exact) == 1:
            product_id = exact[0]["productId"]
            if lanes[product_id] and lanes[product_id] <= STANDARD:
                row.update(minimum=sorted(lanes[product_id]), status="matched", productIDs=[product_id])


def linked_market_products(card_id, card, detail, set_id, official_count, products):
    if (detail["id"] != card_id or detail["set"]["id"] != set_id
            or not identity_agrees(card, detail, "localId")):
        raise ValueError(f"Provider detail identity differs for {card_id}")
    linked = defaultdict(set)
    for key, value in ((detail.get("pricing") or {}).get("tcgplayer") or {}).items():
        if key in LINKED_PRICE_LANES and isinstance(value, dict) and type(value.get("productId")) is int:
            linked[value["productId"]].add(LINKED_PRICE_LANES[key])
    return [dict(product, subtypes=sorted(linked[product["productId"]])) for product in products
            if not product["subtypes"] and product["productId"] in linked
            and re.fullmatch(r"0*" + str(official_count), product["number"].partition("/")[2].strip())]


def english_details(card, kind):
    return [
        row for row in card.get("variants_detailed") or []
        if row.get("type") == kind and (row.get("size") or "standard").lower() == "standard"
        and (row.get("languages") is None or "en" in {language.lower() for language in row["languages"]})
    ]


def has_plain_market_lane(card, *lanes):
    prices = (card.get("pricing") or {}).get("tcgplayer") or {}
    return any(prices.get(lane) is not None for lane in lanes)


def cosmos_holo_aggregate(card, variants):
    cosmos_slots = sorted(
        variant for variant in variants
        if variant in {"cosmos", "pokemonObject|holo|cosmos|"} or variant.startswith("pokemonStamp|cosmos|")
    )
    if "holo" not in variants or not cosmos_slots:
        return []
    if (card.get("variants") or {}).get("holo") is not True:
        return []
    if has_plain_market_lane(card, "holo", "holofoil"):
        return []
    details = english_details(card, "holo")
    if details and all((row.get("foil") or "").lower() == "cosmos" for row in details):
        return cosmos_slots
    return []


def ascended_reverse_aggregate(card, variants, market):
    if card["set"]["id"] != "me02.5" or "reverse" not in variants or "reverse" in market:
        return []
    if (card.get("variants") or {}).get("reverse") is not True or has_plain_market_lane(card, "reverse", "reverse-holofoil"):
        return []
    patterns = {
        ASCENDED_REVERSE_PATTERNS.get((row.get("foil") or "").lower())
        for row in english_details(card, "reverse")
    }
    if len(patterns) == 2 and "energy" in patterns and patterns <= variants and patterns <= market:
        return sorted(patterns)
    return []


def derive_aggregates(evidence, by_set, patterns_for_card):
    receipt = read_json(evidence / "receipts.json")
    files = capture_files(evidence, {
        "files": [dict(item, file=item["id"] + ".json") for item in receipt["files"]],
    })
    snapshot_cards = {}
    for set_id, slots in by_set.items():
        for slot in slots:
            card_id = slot["providerID"]
            row = snapshot_cards.setdefault(card_id, {
                "setID": set_id, "name": slot["name"], "number": slot["collectorNumber"], "variants": set(),
            })
            if slot.get("masterSetVariant"):
                row["variants"].add(slot["masterSetVariant"]["id"])
    aggregates = {}
    for relative in sorted(files):
        card_id = relative.stem
        url = f"https://api.tcgdex.net/v2/en/cards/{card_id}"
        raw = json.loads(captured(evidence, files, relative, url))
        row = snapshot_cards[card_id]
        if raw["id"] != card_id or raw["set"]["id"] != row["setID"] or not identity_agrees(row, raw, "localId"):
            raise ValueError(f"Foil capture identity differs for {card_id}")
        if patterns := patterns_for_card(raw, row["variants"]):
            aggregates[card_id] = patterns
    return aggregates, receipt


def ascended_market_evidence(repo, evidence, aggregate_baseline):
    report = read_json(evidence / "market-report.json")
    group = report["tcgplayerGroupID"]
    cards, sources, _ = checklist(repo, "me02.5", snapshot=aggregate_baseline)
    if report["setID"] != "me02.5" or report["checklistSources"] != sources:
        raise ValueError("Ascended Heroes market report differs from the checklist")
    raw = {kind: (evidence / f"market-{kind}.json").read_bytes() for kind in ("products", "prices")}
    for kind, value in raw.items():
        expected = {"url": f"https://tcgcsv.com/tcgplayer/3/{group}/{kind}", "sha256": digest(value)}
        if report["marketSources"][kind] != expected:
            raise ValueError(f"Ascended Heroes market {kind} differs from the report")
    comparison = compare(cards, {}, numbered_products(raw["products"], raw["prices"], group))
    return {card_id: set(row["market"]) for card_id, row in comparison.items() if "market" in row}, report["marketSources"]


def released_normal_scope(evidence, candidate):
    receipt = read_json(evidence / "bound-receipt.json")
    files = capture_files(evidence, receipt)
    set_id, group = receipt["providerSetID"], receipt["marketGroupID"]
    set_url = f"https://api.tcgdex.net/v2/en/sets/{set_id}"
    provider = json.loads(captured(evidence, files, "provider-set.json", set_url))
    payload_path = candidate / "catalog-payload.json"
    snapshot_path = candidate / "pokemon-catalog-snapshot.json"
    payload, snapshot = read_json(payload_path), read_json(snapshot_path)
    descriptor = next((row for row in payload["sets"] if row["providerSetID"] == set_id), None)
    if (provider["id"] != set_id or not descriptor or descriptor["recognitionKind"] != "expansion"
            or provider["releaseDate"] > payload["generatedAt"][:10]):
        raise ValueError("The retained candidate does not describe the released provider expansion")
    primary = unique_cards(provider["cards"])
    reviewed = {row["providerCardID"]: {
        "name": row["name"], "number": str(row["localID"]), "checklist": ["normal"],
    } for row in snapshot["checklists"][set_id]}
    if len(reviewed) != len(primary) or set(reviewed) != set(primary):
        raise ValueError("The candidate checklist does not match the retained set scope")
    for card_id, row in reviewed.items():
        url = f"https://api.tcgdex.net/v2/en/cards/{card_id}"
        card = json.loads(captured(evidence, files, f"cards/{card_id}.json", url))
        flags = card.get("variants") or {}
        details = card.get("variants_detailed") or []
        if (card["id"] != card_id or card["set"]["id"] != set_id or not identity_agrees(row, card, "localId")
                or flags.get("normal") is not True or any(flags.get(key) for key in ("holo", "reverse", "firstEdition"))
                or any(detail.get("type") != "normal" or detail.get("foil") or detail.get("stamp") for detail in details)):
            raise ValueError(f"Released card {card_id} differs from the uniform Normal placeholder")
    marker_url = "https://tcgcsv.com/last-updated.txt"
    start = captured(evidence, files, "market-start.txt", marker_url)
    end = captured(evidence, files, "market-end.txt", marker_url)
    if start != end or start.decode().strip() != receipt["marketBuild"]:
        raise ValueError("Released set market capture crossed builds")
    directory = json.loads(captured(evidence, files, "market-groups.json", "https://tcgcsv.com/tcgplayer/3/groups"))
    group_name = next(row["name"] for row in directory["results"] if row["groupId"] == group)
    if name_key(group_name.split(": ", 1)[-1]) != name_key(provider["name"]):
        raise ValueError("Released set market group differs from provider identity")
    raw = {kind: captured(evidence, files, f"market-{kind}.json", f"https://tcgcsv.com/tcgplayer/3/{group}/{kind}")
           for kind in ("products", "prices")}
    matches = match_cards(reviewed, primary, reviewed, numbered_products(raw["products"], raw["prices"], group))
    return set_id, matches, {
        "capture": receipt, "candidatePayloadSHA256": digest(payload_path.read_bytes()),
        "candidateSnapshotSHA256": digest(snapshot_path.read_bytes()), "cards": matches,
    }


def derive(repo, evidence, foil_evidence, reverse_evidence, released_evidence=None, candidate=None,
           *, aggregate_baseline=None, alternate_evidence=None, detail_evidence=None):
    snapshot = repo / SNAPSHOT
    baseline_root = aggregate_baseline or snapshot
    baseline = read_json(baseline_root / "manifest.json")
    legacy_sets, legacy_resources = defaultdict(list), {}
    for entry in baseline["entries"]:
        resource = entry["resource"]
        if Path(resource).is_absolute() or ".." in Path(resource).parts or resource == "manifest.json":
            raise ValueError(f"Unsafe checklist resource {resource}")
        raw = (baseline_root / resource).read_bytes()
        slots = json.loads(raw)
        legacy_sets[entry["providerID"]].extend(slots)
        legacy_resources[resource] = (digest(raw), {slot["providerID"] for slot in slots})
    holo_aggregates, foil_receipt = derive_aggregates(foil_evidence, legacy_sets, cosmos_holo_aggregate)
    market, reverse_market_sources = ascended_market_evidence(repo, reverse_evidence, baseline_root)
    reverse_aggregates, reverse_receipt = derive_aggregates(
        reverse_evidence, {"me02.5": legacy_sets["me02.5"]},
        lambda card, variants: ascended_reverse_aggregate(card, variants, market.get(card["id"], set())),
    )
    repaired_cards = holo_aggregates.keys() | reverse_aggregates.keys()
    aggregate_sources = {
        resource: sha256 for resource, (sha256, ids) in sorted(legacy_resources.items())
        if repaired_cards & ids
    }
    previous_path = snapshot / "legacy-finish-evidence.json"
    previous = read_json(previous_path) if previous_path.is_file() else {}
    if aggregate_baseline is None:
        # Replay from a shallow checkout only while the bundled bytes still
        # reproduce the reviewed bindings.
        if previous.get("aggregateChecklistSources") != aggregate_sources:
            raise ValueError(
                "Supply the checklist directory used for the review with --aggregate-baseline. "
                f"If the review used the current bundle, run from the repository root with --aggregate-baseline {SNAPSHOT}."
            )

    manifest = read_json(snapshot / "manifest.json")
    by_set = defaultdict(list)
    for entry in manifest["entries"]:
        by_set[entry["providerID"]].extend(read_json(snapshot / entry["resource"]))
    if previous.get("alternateMarketEvidence") and alternate_evidence is None:
        raise ValueError("Supply --alternate-market-evidence to replay the bundled alternate-art evidence")
    alternate_products, alternate_receipt = ({}, {}) if alternate_evidence is None else alternate_market_products(
        alternate_evidence, manifest["entries"], by_set)
    if previous.get("linkedMarketEvidence") and detail_evidence is None:
        raise ValueError("Supply --provider-detail-evidence to replay the bundled linked-market evidence")
    detail_files = {} if detail_evidence is None else capture_files(detail_evidence, read_json(detail_evidence / "receipts.json"))
    detail_receipts = {}
    scope = {}
    for set_id, rows in sorted(by_set.items()):
        if set_id not in REVIEWED_SETS and rows and all(
            (row.get("masterSetVariant") or {}).get("id") == "normal" for row in rows
        ):
            cards, sources, _ = checklist(repo, set_id)
            scope[set_id] = (cards, sources)
    groups = read_json(evidence / "group-map.json")
    if set(groups) != set(scope):
        raise ValueError("Market group mapping differs from the Normal-only bundle scope")

    receipt = read_json(evidence / "receipts.json")
    secondary_receipt = read_json(evidence / "secondary-receipts.json")
    files = capture_files(evidence, receipt)
    secondary_files = capture_files(evidence, secondary_receipt)
    start = (evidence / "market-build-start.txt").read_bytes()
    if start != (evidence / "market-build-end.txt").read_bytes() or start.decode().strip() != receipt["marketBuild"]:
        raise ValueError("Market capture crossed source builds")
    group_index_path = evidence / "pokemon-groups.json"
    group_index = {item["groupId"]: item["name"] for item in read_json(group_index_path)["results"]}

    output, report = {}, {}
    for set_id, (cards, sources) in scope.items():
        primary_file = f"TCGdex/sets/{set_id}.json"
        primary = json.loads(captured(evidence, files, primary_file, f"https://api.tcgdex.net/v2/en/sets/{set_id}"))
        if primary["id"] != set_id:
            raise ValueError(f"TCGdex set identity differs for {set_id}")
        secondary_file = f"PokemonTCG/{set_id}.json"
        if set_id in secondary_receipt["missingSets"]:
            secondary = {}
        else:
            url = f"https://raw.githubusercontent.com/PokemonTCG/pokemon-tcg-data/{secondary_receipt['commit']}/cards/en/{set_id}.json"
            secondary = unique_cards(json.loads(captured(evidence, secondary_files, secondary_file, url)))

        titles = {name_key(primary["name"])}
        titles.update({"sm1": {"sm base set"}, "xy1": {"xy base set"}}.get(set_id, ()))
        products = defaultdict(list)
        unnumbered_market = None
        for group_id in groups[set_id]:
            name = re.sub(r"^(SM|XY|BW) - ", "", group_index[group_id], flags=re.IGNORECASE)
            if name_key(name.removesuffix(": Radiant Collection")) not in titles:
                raise ValueError(f"Market group {group_id} does not name {set_id}")
            url = f"https://tcgcsv.com/tcgplayer/3/{group_id}"
            raw_products = captured(evidence, files, f"TCGCSV/{group_id}-products.json", f"{url}/products")
            raw_prices = captured(evidence, files, f"TCGCSV/{group_id}-prices.json", f"{url}/prices")
            if set_id == "sm1" and group_id == 1863:
                unnumbered_market = raw_products, raw_prices, group_id
            for number, rows in numbered_products(raw_products, raw_prices, group_id).items():
                products[number].extend(rows)

        primary_cards = unique_cards(primary["cards"])
        matches = match_cards(cards, primary_cards, secondary, products)
        if unnumbered_market is not None:
            apply_unnumbered_energy(matches, cards, primary_cards, secondary, *unnumbered_market)
        for card_id in matches.keys() & alternate_products.keys():
            row = matches[card_id]
            if row["minimum"] or row["status"] != "exact standard market product unavailable":
                continue
            number = local_number(row["number"])
            extra = match_cards({card_id: cards[card_id]}, primary_cards, secondary,
                                {number: alternate_products[card_id]})[card_id]
            if extra["minimum"]:
                row.update(minimum=extra["minimum"], status="matched", productIDs=extra["productIDs"],
                           marketGroup=ALTERNATE_ART_MARKET_GROUP)
                row["otherProductsAtNumber"] = sorted(set(row["otherProductsAtNumber"]) | set(extra["otherProductsAtNumber"]))
        official_count = (primary.get("cardCount") or {}).get("official")
        for card_id, row in matches.items():
            if row["status"] != "exact standard market product unavailable" or not official_count:
                continue
            number = local_number(row["number"])
            detail_path = Path(f"{card_id}.json")
            if not products[number] or detail_path not in detail_files:
                continue
            detail = json.loads(captured(detail_evidence, detail_files, detail_path,
                                         f"https://api.tcgdex.net/v2/en/cards/{card_id}"))
            linked = linked_market_products(card_id, cards[card_id], detail, set_id, official_count, products[number])
            extra = match_cards({card_id: cards[card_id]}, primary_cards, secondary, {number: linked})[card_id]
            if extra["minimum"]:
                row.update(minimum=extra["minimum"], status="matched", productIDs=extra["productIDs"])
                row["otherProductsAtNumber"] = sorted(set(row["otherProductsAtNumber"]) - set(extra["productIDs"]))
                detail_receipts[card_id] = detail_files[detail_path]
        report[set_id] = {"checklistSources": sources, "marketGroups": groups[set_id], "cards": matches}
        for card_id, row in matches.items():
            if card_id in output or card_id != set_id + "-" + row["number"]:
                raise ValueError(f"Ambiguous or inconsistent bundled ID {card_id}")
            minimum = row["minimum"]
            output[card_id] = {
                "setID": set_id, "number": row["number"], "minimum": minimum,
                "normalNeedsReview": "normal" not in minimum,
            }
            if row.get("isUnnumbered"):
                output[card_id]["isUnnumbered"] = True
    released_report = {}
    if released_evidence is not None:
        set_id, matches, released_report = released_normal_scope(released_evidence, candidate)
        if set_id in scope:
            raise ValueError(f"Released evidence overlaps the historical scope for {set_id}")
        for card_id, row in matches.items():
            if card_id in output or card_id != set_id + "-" + row["number"]:
                raise ValueError(f"Ambiguous released card ID {card_id}")
            output[card_id] = {
                "setID": set_id, "number": row["number"], "minimum": row["minimum"],
                "normalNeedsReview": "normal" not in row["minimum"],
            }
    alternate_provenance = {"alternateMarketEvidence": alternate_receipt} if alternate_receipt else {}
    linked_provenance = {"linkedMarketEvidence": detail_receipts} if detail_receipts else {}
    return {
        "schemaVersion": 1, "marketBuild": receipt["marketBuild"],
        "secondaryCatalogCommit": secondary_receipt["commit"], "cards": output,
        "holoAggregates": holo_aggregates, "reverseAggregates": reverse_aggregates,
        "aggregateChecklistSources": aggregate_sources, **alternate_provenance, **linked_provenance,
    }, {
        "schemaVersion": 1, "market": receipt, "independentCatalog": secondary_receipt,
        "marketGroupIndexSHA256": digest(group_index_path.read_bytes()), "sets": report,
        "foilEvidence": foil_receipt, "holoAggregates": holo_aggregates,
        "reverseEvidence": reverse_receipt, "reverseMarketSources": reverse_market_sources,
        "reverseAggregates": reverse_aggregates,
        "aggregateChecklistSources": aggregate_sources,
        "releasedSetEvidence": released_report, **alternate_provenance, **linked_provenance,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--foil-evidence", required=True, type=Path)
    parser.add_argument("--reverse-evidence", required=True, type=Path)
    parser.add_argument("--aggregate-baseline", type=Path,
                        help="Original checklist directory. Defaults to the bundle when its reviewed hashes match.")
    parser.add_argument("--released-evidence", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--alternate-market-evidence", type=Path,
                        help="Retained Alternate Art Promos products, prices, build markers and verified-alternates.json receipt")
    parser.add_argument("--provider-detail-evidence", type=Path,
                        help="Retained TCGdex detail responses and receipts.json with exact market product links")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    if (args.released_evidence is None) != (args.candidate is None):
        parser.error("--released-evidence and --candidate are required together")
    output, report = derive(ROOT, args.evidence, args.foil_evidence, args.reverse_evidence,
                            args.released_evidence, args.candidate, aggregate_baseline=args.aggregate_baseline,
                            alternate_evidence=args.alternate_market_evidence, detail_evidence=args.provider_detail_evidence)
    write_json(args.output, output)
    write_json(args.report, report)
    count = sum(bool(row["minimum"]) for row in output["cards"].values())
    set_count = len({row["setID"] for row in output["cards"].values()})
    print(f"Retained {count} minimum finish lists across {len(output['cards'])} cards in {set_count} sets")
    print(f"Corroborated {len(output['holoAggregates'])} Cosmos aggregate Holo flags")
    print(f"Corroborated {len(output['reverseAggregates'])} Ascended Heroes aggregate Reverse flags")


if __name__ == "__main__":
    main()
