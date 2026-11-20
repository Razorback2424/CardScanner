#!/usr/bin/env python3
"""Propose reviewed Yu-Gi-Oh! release-name aliases from a builder exceptions ledger.

TCGplayer and YGOPRODeck often name the same release differently ("The Legend
of Blue Eyes White Dragon" vs "Legend of Blue Eyes White Dragon", "2025
Mega-Pack" vs "2025 Mega-Pack Tin"). The builder only accepts a source printing
whose set name equals the marketplace group name, so these codes stay
`unreviewedCorrespondence` even when the printed code and card agree.

When a group holds several sub-releases (waves, Special Edition promos), the
products under one prefix can name different releases. Then each printed code
whose products agree on exactly one name gets an alias for that exact code.

An alias is proposed for a (group, code prefix) only when every open product in
that scope has a canonical card, the same printed code appears in YGOPRODeck for
that same card, and all of those source rows share exactly one set name. The
printed set code is the collector's identity for a release, so this is the
evidence; the name is only the label. Rarity is still checked exactly by the
builder, and aliases never grant edition, artwork or pricing authority.

Reads the `<report>.ledger.json` sidecar written by build_yugioh_catalog.py.
Offline only. `--write` merges proposals into yugioh_correspondence_rules.json.
"""
from __future__ import annotations

import argparse
import collections
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import catalog_exceptions
from yugioh_official_inventory import norm

RULES = ROOT / "yugioh_correspondence_rules.json"
REASON = "unreviewedCorrespondence"


def prefix(code: str) -> str:
    return code.split("-", 1)[0] + "-"


def propose(rows: list[dict]) -> tuple[list[dict], list[dict]]:
    """Return (aliases, refusals) from ledger rows. Deterministic."""
    scopes = collections.defaultdict(dict)  # (groupID, prefix) -> {productID: (code, names)}
    group_names = {}
    for entry in rows:
        if entry["game"] != "yugioh" or entry["reason"] != REASON:
            continue
        code = entry["identity"]
        sources = entry["evidence"].get("sourceRows", [])
        for product in entry["evidence"].get("products", []):
            if product.get("productID") is None:
                continue
            gid = product["groupID"]
            group_names[gid] = product["group"]
            names = {source["setName"] for source in sources if source["cardID"] == product["cardID"]}
            if product["cardID"] is None or norm(product["group"]) in {norm(name) for name in names}:
                continue  # unresolved card, or already named exactly: an alias would not be the fix
            scopes[(gid, prefix(code))][product["productID"]] = (code, names)
    aliases, refusals = collections.defaultdict(lambda: {"prefixes": set(), "products": 0, "codes": set()}), []
    per_code = collections.defaultdict(lambda: {"products": 0, "codes": set()})
    for (gid, code_prefix), products in sorted(scopes.items()):
        # A product whose card has no source row under its printed code neither supports
        # nor contradicts an alias; it stays open whatever the alias says.
        supported = {pid: value for pid, value in products.items() if value[1]}
        candidates = [names for _, names in supported.values()]
        common = set.intersection(*candidates) if candidates else set()
        if not common and candidates:
            # One TCGplayer group often holds several sub-releases (Duel Terminal 5a and
            # 5b, tin waves, Special Edition promos filed under the main set). Fall back
            # to the printed code: each code whose products agree on exactly one name
            # gets an alias for that exact code only. Other codes stay open.
            by_code = collections.defaultdict(list)
            for code, names in supported.values():
                by_code[code].append(names)
            refused_codes = []
            for code, name_sets in sorted(by_code.items()):
                agreed = set.intersection(*name_sets)
                if len(agreed) != 1:
                    refused_codes.append(code)
                    continue
                entry = per_code[(gid, next(iter(agreed)))]
                entry["codes"].add(code)
                entry["products"] += len(name_sets)
            if refused_codes:
                refusals.append({"groupID": gid, "groupName": group_names[gid], "codePrefix": code_prefix,
                                 "products": sum(len(by_code[c]) for c in refused_codes),
                                 "reason": "ambiguousSetName", "codes": refused_codes,
                                 "setNames": sorted(set().union(*(n for c in refused_codes for n in by_code[c])))})
            continue
        if len(common) != 1:
            refusals.append({"groupID": gid, "groupName": group_names[gid], "codePrefix": code_prefix,
                             "products": len(products),
                             "reason": "noSourceRow" if not candidates else "noCommonSetName" if not common else "ambiguousSetName",
                             "setNames": sorted(set().union(*candidates)) if candidates else []})
            continue
        name = next(iter(common))
        alias = aliases[(gid, name)]
        alias["prefixes"].add(code_prefix)
        alias["products"] += len(supported)
        alias["codes"].update(code for code, _ in supported.values())
    result = []
    for (gid, name), alias in sorted(aliases.items()):
        result.append({"id": f"release-name-{gid}", "groupID": gid, "groupName": group_names[gid], "setName": name,
                       "codePrefixes": sorted(alias["prefixes"]),
                       "evidence": {"rule": "printed-code-and-card-agree-v1", "products": alias["products"],
                                    "codes": len(alias["codes"]), "exampleCodes": sorted(alias["codes"])[:3]}})
    for (gid, name), alias in sorted(per_code.items()):
        result.append({"id": f"release-name-{gid}-codes-" + norm(name).replace(" ", "-"), "groupID": gid,
                       "groupName": group_names[gid], "setName": name, "codePrefixes": [],
                       "codes": sorted(alias["codes"]),
                       "evidence": {"rule": "printed-code-and-card-agree-per-code-v1", "products": alias["products"],
                                    "codes": len(alias["codes"]), "exampleCodes": sorted(alias["codes"])[:3]}})
    ids = collections.Counter(alias["id"] for alias in result)
    for alias in result:
        if ids[alias["id"]] > 1:
            alias["id"] += "-" + norm(alias["setName"]).replace(" ", "-")
    return result, refusals


def merge(document: dict, aliases: list[dict], reviewed_at: str, ledger_source: dict) -> dict:
    """Replace generated aliases; keep every other rule untouched.

    An alias identical to one already reviewed keeps its original review record.
    """
    merged = dict(document)
    review_keys = ("reviewedAt", "ledger")
    previous = {alias["id"]: alias for alias in document.get("setNameAliases", [])}
    def unchanged(alias):
        old = previous.get(alias["id"])
        return old is not None and {k: v for k, v in old.items() if k not in review_keys} == alias
    merged["setNameAliases"] = [previous[alias["id"]] if unchanged(alias)
                                else dict(alias, reviewedAt=reviewed_at, ledger=ledger_source) for alias in aliases]
    return merged


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ledger", type=pathlib.Path)
    parser.add_argument("--refusals", type=pathlib.Path, help="Write the scopes that did not qualify, for review")
    parser.add_argument("--write", action="store_true", help=f"Merge proposals into {RULES.name}")
    parser.add_argument("--reviewed-at", help="Review date recorded on each alias (YYYY-MM-DD); required with --write")
    args = parser.parse_args(argv)
    rows = catalog_exceptions.read_ledger(args.ledger)
    source = json.loads(args.ledger.read_text()).get("source", {})
    aliases, refusals = propose(rows)
    print(f"{len(aliases)} aliases over {sum(a['evidence']['products'] for a in aliases)} products; "
          f"{len(refusals)} scopes refused {dict(collections.Counter(r['reason'] for r in refusals))}")
    if args.refusals:
        args.refusals.write_text(json.dumps(refusals, indent=1, ensure_ascii=False) + "\n")
    if args.write:
        if not args.reviewed_at:
            parser.error("--reviewed-at is required with --write")
        document = merge(json.loads(RULES.read_text()), aliases, args.reviewed_at, source)
        RULES.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
