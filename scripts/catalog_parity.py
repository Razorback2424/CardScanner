#!/usr/bin/env python3
"""Compare complete local catalog exports.

Pass a Yu-Gi-Oh catalog.json, a One Piece release envelope or payload, or a
Lorcana seed directory containing discovery.json and market.json. Pass the
repository root for Pokémon or a retained Scryfall sets and JSONL directory
for Magic.

An allowlist is a JSON list of reported changes with a nonempty `reason` on
each row. Each approval pins the exact before and after record digests.
Signature and release-size validation remain with the publisher and preflight.
"""
from __future__ import annotations

import argparse
import base64
from decimal import Decimal
import gzip
from hashlib import sha256
import json
from pathlib import Path
import sys

from audit_catalog_coverage import Audit, decode_json, footer_key, one_piece_registry, uid, validate_pokemon_slots
from build_lorcana_market_catalog import validate_source_universes
from market_price_feeds import read_site

MIRROR_CATEGORIES = {"yugioh": 2, "pokemon": 3, "one-piece": 68, "lorcana": 71}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def indexed(rows, key):
    result = {}
    for row in rows:
        identity = str(key(row))
        if not identity or identity in result:
            raise ValueError(f"Empty or duplicate identity: {identity!r}")
        result[identity] = row
    return result


def yugioh(document):
    if document["schemaVersion"] != 1:
        raise ValueError("Unsupported Yu-Gi-Oh catalog schema")
    sets = indexed(document["sets"], lambda row: row["g"])
    cards = indexed(document["cards"], lambda row: row["id"])
    if not sets or not cards or not document["printings"]:
        raise ValueError("Yu-Gi-Oh catalog must include sets, cards and printings")
    printings, finishes, mappings, priced = {}, {}, {}, {}
    for is_reference, rows in ((False, document["printings"]), (True, document.get("referencePrintings", []))):
        for identity, row in indexed(rows, lambda row: row["id"].lower()).items():
            if identity in printings:
                raise ValueError(f"Duplicate printing across catalogs: {identity}")
            if str(row["g"]) not in sets or not 0 <= row["k"] < len(cards):
                raise ValueError(f"Unknown set or canonical card for {identity}")
            membership = indexed(row.get("m") or [], lambda item: item["e"])
            excluded = {"id", "k", "e", "ec", "ee", "m", "p", "pg", "pn", "pe"}
            printings[identity] = {**{key: value for key, value in row.items() if key not in excluded},
                                   "canonicalID": document["cards"][row["k"]]["id"],
                                   "reference": is_reference}
            finishes[identity] = {"editions": sorted(row["e"]), "certified": row["ec"], "evidence": row.get("ee"),
                                  "membership": {lane: item["t"] for lane, item in membership.items()}}
            if row.get("p") is not None:
                mappings[identity] = {"provider": "tcgplayer", "productID": row["p"],
                                      "groupID": row.get("pg", row["g"]), "productName": row["pn"],
                                      "lanes": sorted(row["e"])}
            priced[identity] = {"coveredEditions": sorted(row["pe"]),
                                "seedQuoteEditions": sorted(lane for lane, item in membership.items()
                                                            if item.get("q") is not None)}
    policy = {key: value for key, value in document.items() if key not in
              {"schemaVersion", "capturedAt", "generation", "sets", "cards", "printings", "referencePrintings"}}
    for key in ("autoEligibleCodes", "incompleteCodes"):
        policy[key] = sorted(policy[key])
    return {"sets": sets, "cards": cards, "printings": printings, "finishes": finishes,
            "marketplaceMappings": mappings, "pricedProducts": priced, "policy": policy}


def read_json(path):
    return decode_json(path.read_bytes(), str(path))


def release_payload(path):
    release = read_json(path)
    if "payload" in release:
        encoded = release["payload"]
        release = decode_json(base64.b64decode(encoded + "=" * (-len(encoded) % 4),
                                               altchars=b"-_", validate=True), str(path))
    return release


def one_piece(path):
    release = release_payload(path)
    if release["catalogKind"] != "one-piece" or release["schemaVersion"] != 1:
        raise ValueError("Unsupported One Piece release")
    registry = release["registry"]
    _, printings, _ = one_piece_registry(registry)
    sets = indexed(registry["products"], lambda row: row["id"])
    if not sets or not printings:
        raise ValueError("One Piece catalog must include products and printings")
    return {
        "sets": sets,
        "printings": {identity: {key: value for key, value in row.items()
                                 if key not in {"id", "marketMappings", "supportedVariantIDs"}}
                      for identity, row in printings.items()},
        "finishes": {identity: sorted(row["supportedVariantIDs"]) for identity, row in printings.items()},
        "marketplaceMappings": {identity: sorted(row["marketMappings"], key=canonical)
                                for identity, row in printings.items() if row["marketMappings"]},
        "cards": indexed(registry["canonicalCards"], lambda row: row["id"]),
        "artworks": indexed(registry["artworks"], lambda row: uid(row["id"])),
        "appearances": indexed(registry["appearances"], lambda row: canonical([uid(row["printingID"]), row["productID"]])),
        "corrections": indexed(registry["corrections"], lambda row: row["id"]),
        "observations": indexed(release["observations"], lambda row: row["id"]),
        "inventories": indexed(release["inventories"], lambda row: canonical([row["provider"], row["snapshotID"]])),
        "variants": indexed(registry["variants"], lambda row: row["id"]),
        "policy": {"indexes": release["indexes"], "rulesVersion": release["rulesVersion"]},
    }


def lorcana(path):
    discovery_path = path / "discovery.json"
    discovery_bytes = discovery_path.read_bytes()
    discovery = decode_json(discovery_bytes, str(discovery_path))
    market = read_json(path / "market.json")
    if discovery["schemaVersion"] != 1 or market["schemaVersion"] != 2:
        raise ValueError("Unsupported Lorcana discovery or physical catalog")
    discovery_hash = sha256(discovery_bytes).hexdigest()
    if market["discoverySHA256"] != discovery_hash:
        raise ValueError("Lorcana physical catalog is bound to different discovery bytes")
    validate_source_universes(discovery["cards"], market)
    sources = indexed(discovery["cards"], lambda row: row["id"])
    printings = indexed(market["physicalPrintings"], lambda row: uid(row["id"]))
    if not sources or not printings:
        raise ValueError("Lorcana catalog must include discovery and physical printings")
    coverage = discovery["coverage"]
    browse = path / "browse-prices.json"
    browse_mappings = {}
    if browse.exists():
        document = read_json(browse)
        if document["schemaVersion"] != 1 or document["discoverySHA256"] != discovery_hash:
            raise ValueError("Lorcana Browse prices are bound to different discovery bytes")
        browse_mappings = indexed(document["entries"], lambda row: canonical([row["sourceID"], row["mapping"]["finish"]]))
        if any(row["sourceID"] not in sources for row in browse_mappings.values()):
            raise ValueError("Unknown Lorcana Browse market mapping source")
    return {
        "sets": coverage["sets"],
        "printings": {identity: {key: value for key, value in row.items()
                                 if key not in {"id", "finishes", "marketMappings"}}
                      for identity, row in printings.items()},
        "finishes": {identity: indexed(row["finishes"], lambda finish: finish["finish"])
                     for identity, row in printings.items()},
        "marketplaceMappings": {identity: indexed(row["marketMappings"], lambda mapping: mapping["finish"])
                                for identity, row in printings.items() if row.get("marketMappings")},
        "browseMarketplaceMappings": browse_mappings,
        "cards": indexed(market["canonicalCards"], lambda row: uid(row["id"])),
        "families": indexed(market["printFamilies"], lambda row: footer_key(row["footer"])),
        "universes": indexed(market["universes"], lambda row: footer_key(row["footer"])),
        "corrections": indexed(market["corrections"], lambda row: uid(row["id"])),
        "discoveryPrintings": sources,
        "sealedProducts": indexed(discovery["sealed"], lambda row: row["id"]),
        "discoveryCoverage": {key: value for key, value in coverage.items() if key not in {"sets", "cardSourceSHA256"}},
    }


def pokemon(path):
    audit = Audit(path)
    root = Path("TradingCardScanner/PokemonChecklistSnapshot")
    release_root = Path("TradingCardScanner/PokemonCatalogRelease")
    manifest = audit.json(root / "manifest.json")
    release = release_payload(path / release_root / "catalog-release.json")
    snapshot = audit.json(release_root / "pokemon-catalog-snapshot.json")
    if release["catalogKind"] != "pokemon" or any(value["schemaVersion"] != 1
                                                  for value in (manifest, release, snapshot)):
        raise ValueError("Unsupported Pokémon release or checklist")
    sets, printings, finishes = {}, {}, {}
    for entry in manifest["entries"]:
        identifier = canonical(entry["set"]["catalogID"])
        if identifier in sets:
            raise ValueError(f"Duplicate Pokémon checklist set: {identifier}")
        sets[identifier] = {key: value for key, value in entry.items() if key != "resource"}
        rows = audit.json(root / entry["resource"])
        validate_pokemon_slots(entry, rows)
        for row in rows:
            finish = row.get("masterSetVariant")
            key = canonical([entry["set"]["catalogID"], row["providerID"], (finish or {}).get("id")])
            printings[key] = {name: value for name, value in row.items() if name != "masterSetVariant"}
            finishes[key] = finish
    signed_sets = indexed(release["sets"], lambda row: row["providerSetID"])
    if not sets or not printings or not signed_sets or set(snapshot["checklistInputs"]) != set(signed_sets):
        raise ValueError("Missing Pokémon checklist sets, printings or signed inputs")
    signed_printings = {}
    for set_id, source in snapshot["checklistInputs"].items():
        for card_id, row in indexed(source["cards"], lambda row: row["id"]).items():
            if row["setID"] != set_id:
                raise ValueError(f"Pokémon printing {card_id} belongs to a different set")
            signed_printings[canonical([set_id, card_id])] = row
    supplementary = {}
    for filename in ("finish-minimums.json", "finish-coverage.json", "finish-coverage-variants.json",
                     "legacy-finish-evidence.json", "reviewed-artwork-printings.json", "reviewed-unnumbered-energy.json"):
        supplementary[filename] = audit.json(root / filename)
    mappings = {}
    for name in ("battle-deck-finishes", "deck-exclusive-normals", "delta-reign-printings",
                 "mcdonalds-2026", "prize-pack-printings"):
        mappings[name] = audit.json(f"publisher/pokemon-{name}.json")
    mappings["reviewedTCGCSV"] = audit.text("TradingCardScanner/Services/PokemonTCGCSVMapping.swift")
    return {"sets": sets, "printings": printings, "finishes": finishes, "signedSets": signed_sets,
            "signedPrintings": signed_printings, "signedChecklists": snapshot["checklists"],
            "rarities": snapshot["cardRarities"], "finishEvidence": supplementary, "marketplaceMappings": mappings}


def magic(path):
    directory = read_json(path / "sets.json")
    if directory["object"] != "list" or directory["has_more"]:
        raise ValueError("Magic set directory is incomplete")
    sets = indexed(directory["data"], lambda row: uid(row["id"]))
    printings, finishes, mappings, priced = {}, {}, {}, {}
    archive = path / "default-cards.jsonl.gz"
    if not archive.exists():
        archive = path / "default-cards.jsonl"
    open_input = gzip.open if archive.suffix == ".gz" else open
    with open_input(archive, "rb") as stream:
        for line in stream:
            if not line.strip():
                continue
            row = json.loads(line)
            if row["object"] != "card":
                raise ValueError("Unexpected object in Magic Default Cards")
            if row["lang"] != "en" or row["digital"] or "paper" not in row["games"]:
                continue
            identity = uid(row["id"])
            set_id = uid(row["set_id"])
            if identity in printings or set_id not in sets or sets[set_id]["code"] != row["set"]:
                raise ValueError(f"Duplicate Magic printing or unknown set: {identity}")
            printings[identity] = {"set": set_id, "number": row["collector_number"], "oracleID": row.get("oracle_id")}
            finishes[identity] = sorted(row["finishes"])
            mappings[identity] = {key: row[key] for key in ("tcgplayer_id", "tcgplayer_etched_id", "cardmarket_id")
                                  if row.get(key) is not None}
            priced[identity] = []
            for lane in ("usd", "usd_foil", "usd_etched", "eur", "eur_foil"):
                value = row["prices"].get(lane)
                if value is not None:
                    amount = Decimal(value)
                    if not amount.is_finite() or amount < 0:
                        raise ValueError(f"Invalid Magic price for {identity} in {lane}")
                    priced[identity].append(lane)
    if not printings:
        raise ValueError("Magic bulk capture has no English paper printings")
    return {"sets": sets, "printings": printings, "finishes": finishes,
            "marketplaceMappings": mappings, "pricedProducts": priced}


READERS = {"yugioh": lambda path: yugioh(read_json(path)), "one-piece": one_piece, "lorcana": lorcana,
           "pokemon": pokemon, "magic": magic}


def mirror_priced_products(directory, category):
    directory = directory.resolve()

    def read_file(path, size):
        source = (directory / path).resolve()
        if not source.is_relative_to(directory):
            raise ValueError(f"Price artifact escapes capture: {path}")
        with source.open("rb") as stream:
            data = stream.read(size + 1)
        if len(data) > size:
            raise ValueError(f"Price artifact exceeds declared size: {path}")
        return data

    files = read_site(read_file("index.json", 1024 * 1024), read_file)
    price_paths = [path for path in files if path.startswith(f"tcgplayer/{category}/") and path.endswith("/prices")]
    if not price_paths:
        raise ValueError(f"Price capture contains no groups for category {category}")
    coverage = {}
    for path in price_paths:
        group = path.split("/")[2]
        products = {row["productId"] for row in json.loads(files[path.rsplit("/", 1)[0] + "/products"])["results"]}
        for row in json.loads(files[path])["results"]:
            if row.get("marketPrice") is not None and row["productId"] in products:
                coverage[canonical([group, row["productId"], row["subTypeName"]])] = True
    return coverage


def compare(before, after):
    changes = []
    for section in sorted(before.keys() | after.keys()):
        left, right = before.get(section, {}), after.get(section, {})
        for identity in sorted(left.keys() | right.keys()):
            old = canonical(left[identity]).encode() if identity in left else None
            new = canonical(right[identity]).encode() if identity in right else None
            if old != new:
                changes.append({"section": section, "identity": identity,
                                "before": sha256(old).hexdigest() if old is not None else None,
                                "after": sha256(new).hexdigest() if new is not None else None})
    return changes


def approvals(path):
    if not path:
        return set()
    rows = json.loads(path.read_bytes())
    keys = {"section", "identity", "before", "after", "reason"}
    if not isinstance(rows, list):
        raise ValueError("Expected a list of approved parity changes")
    result = set()
    for row in rows:
        if set(row) != keys or not isinstance(row["reason"], str) or not row["reason"].strip():
            raise ValueError("Every approved change must include its exact diff and a reason")
        result.add(canonical({key: value for key, value in row.items() if key != "reason"}))
    if len(result) != len(rows):
        raise ValueError("Duplicate parity approvals")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", choices=sorted(READERS))
    parser.add_argument("--before", required=True, type=Path)
    parser.add_argument("--after", required=True, type=Path)
    parser.add_argument("--allowlist", type=Path)
    parser.add_argument("--before-prices", type=Path, help="Complete captured market-prices/v1 directory")
    parser.add_argument("--after-prices", type=Path, help="Complete captured market-prices/v1 directory")
    args = parser.parse_args(argv)
    if bool(args.before_prices) != bool(args.after_prices) or (args.before_prices and args.game not in MIRROR_CATEGORIES):
        parser.error("provide both price captures for a game that uses the mirror")
    try:
        before, after = (READERS[args.game](path) for path in (args.before, args.after))
        if args.before_prices:
            category = MIRROR_CATEGORIES[args.game]
            before["mirrorPricedProducts"] = mirror_priced_products(args.before_prices, category)
            after["mirrorPricedProducts"] = mirror_priced_products(args.after_prices, category)
        expected = approvals(args.allowlist)
        actual = {canonical(change) for change in compare(before, after)}
    except (OSError, ValueError, TypeError, AttributeError, KeyError, IndexError, ArithmeticError) as error:
        print(f"catalog parity: {error}", file=sys.stderr)
        return 2
    print(f"{args.game}: compared {len(before['sets'])} → {len(after['sets'])} sets and "
          f"{len(before['printings'])} → {len(after['printings'])} printings")
    for state, changes in (("unexpected", actual - expected), ("unused approval", expected - actual)):
        for change in sorted(changes):
            print(f"{state}: {change}", file=sys.stderr)
    return int(actual != expected)


if __name__ == "__main__":
    sys.exit(main())
