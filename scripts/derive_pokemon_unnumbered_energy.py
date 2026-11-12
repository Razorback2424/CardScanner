#!/usr/bin/env python3
"""Replay the reviewed English unnumbered Energy families from retained sources."""
from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
import json
import re

from certify_pokemon_finish_coverage import read_json, write_json
from market_price_feeds import digest, validate_response


ENERGY_NAMES = tuple(f"{name} Energy" for name in (
    "Grass", "Fire", "Water", "Lightning", "Psychic", "Fighting", "Darkness", "Metal", "Fairy",
))
ORDINARY_LANES = {"Normal", "Reverse Holofoil"}
FAMILIES = (
    ("sm1", "Sun & Moon", "SUM", 2017, 1863, " (2017 Unnumbered)"),
    ("sm9", "Team Up", "TEU", 2019, 2377, " (2019 Unnumbered)"),
    ("swsh1", "Sword & Shield", "SSH", 2020, 2585, ""),
    ("swsh9", "Brilliant Stars", "BRS", 2022, 2948, " (2022 Unnumbered)"),
)
LEAGUE_FAMILIES = (
    (2005, " (2005 Unnumbered)", ENERGY_NAMES[:6], "normal", "Normal", "League & Championship Cards"),
    (2006, " (2006 Unnumbered)", ENERGY_NAMES[:6], "normal", "Normal", "League & Championship Cards"),
    (2009, " (2009 Unnumbered POP Promo)", ENERGY_NAMES[:8], "holo", "Holofoil", "Crosshatch POP Promo"),
    (2010, " (2010 Unnumbered HGSS Style Non-Holo)", ENERGY_NAMES[:8], "normal", "Normal", "HGSS Style"),
)


def exact_products(rows, year, suffix, names=ENERGY_NAMES):
    expected = {name + suffix: name for name in names}
    products = {}
    for row in rows:
        name = expected.get(row["name"])
        if name is None:
            continue
        fields = defaultdict(list)
        for field in row["extendedData"]:
            fields[field["name"]].append(field.get("value"))
        generic_type = year == 2020 or (year == 2009 and name in {"Darkness Energy", "Fighting Energy"})
        expected_type = "Basic Energy" if generic_type else f"Basic {name}"
        if (name in products or fields["Card Type"] != [expected_type]
                or any(value.strip() for value in fields["Number"])
                or (year == 2020 and fields["CardText"] != ["©2020 Unnumbered"])):
            raise ValueError(f"Unproven unnumbered product {row['productId']} for {name}")
        products[name] = row
    if products.keys() != set(names):
        raise ValueError(f"Incomplete reviewed Energy group for {year} {suffix}")
    return products


def require_skus(detail, product, group, lanes):
    attrs = detail.get("customAttributes") or {}
    skus = detail.get("skus") or []
    if (detail.get("productId") != product["productId"] or detail.get("setId") != group
            or detail.get("productName") != product["name"] or detail.get("sealed") is not False
            or detail.get("productTypeName") != "Cards" or (attrs.get("number") or "").strip()
            or {(row.get("language"), row.get("variant")) for row in skus}
            != {("English", lane) for lane in lanes}):
        raise ValueError(f"SKU identity or finish differs for {product['productId']}")


def derive(capture, legacy):
    start = (capture / "market-build-start.txt").read_bytes()
    if not start.strip() or start != (capture / "market-build-end.txt").read_bytes():
        raise ValueError("Energy capture crossed market builds")
    sources = {}

    def bound(path):
        raw = (capture / path).read_bytes()
        sources[path] = digest(raw)
        return raw

    def read_vision(path):
        observations = {}
        for line in bound(path).splitlines():
            observation = json.loads(line)
            name = observation["image"]
            if name in observations:
                raise ValueError(f"Duplicate Energy image evidence {name}")
            observations[name] = observation["readings"]
        return observations

    readings = read_vision("vision-footers.jsonl")
    brilliant = read_vision("brilliant-vision-footers.jsonl")
    league = read_vision("league-vision-footers.jsonl")

    def market(group):
        rows = validate_response(bound(f"{group}-products.json"), 3, group, "products")
        lanes = defaultdict(set)
        for row in validate_response(bound(f"{group}-prices.json"), 3, group, "prices"):
            lanes[row["productId"]].add(row["subTypeName"])
        return rows, lanes

    wave_group = 1840
    wave_rows, wave_lanes = market(wave_group)
    wave = exact_products(wave_rows, 2017, " (2017 Unnumbered) (Wave Foil)")
    deck_products = exact_products(wave_rows, 2013, " (2013 Unnumbered)")
    deck_cards = []
    deck_footer_observed = False
    for name in ENERGY_NAMES:
        product = deck_products[name]
        product_id = product["productId"]
        lanes = {"Normal", "Holofoil"}
        detail = json.loads(bound(f"details/{product_id}.json"))
        require_skus(detail, product, wave_group, lanes)
        description = re.sub(r"<[^>]+>", "", detail["customAttributes"].get("description", ""))
        if description.strip() != "Unnumbered with 2013 copyright date." or wave_lanes[product_id] != lanes:
            raise ValueError(f"2013 copyright or finish evidence differs for {product_id}")
        image = f"{product_id}.jpg"
        bound(f"details/{image}")
        observed = readings[image]
        footer = "©2013 Pokémon"
        if (observed["header"] not in (["ENERGY"], ["NERGY"])
                or any(reading != footer for region in ("scanner", "footer") for reading in observed[region])):
            raise ValueError(f"Image conflicts with the reviewed Deck Exclusives product {product_id}")
        deck_footer_observed |= footer in observed["footer"] or footer in observed["scanner"]
        deck_cards.append({"providerID": f"tcgplayer:{product_id}", "localID": str(product_id), "name": name,
                           "finishProducts": {"normal": product_id, "holo": product_id}})
    if not deck_footer_observed:
        raise ValueError("The 2013 Deck Exclusives capture has no readable copyright control")
    families = [{"providerSetID": "tcgplayer:1840:2013", "setName": "2013 Basic Energy (Deck Exclusives)",
                 "setCode": "Energy", "year": 2013, "officialCount": 0, "cards": deck_cards}]
    league_group = 1539
    league_rows, league_lanes = market(league_group)
    for year, suffix, names, finish, lane, label in LEAGUE_FAMILIES:
        products = exact_products(league_rows, year, suffix, names)
        cards = []
        saw_year = False
        for name in names:
            product = products[name]
            product_id = product["productId"]
            detail = json.loads(bound(f"league-details/{product_id}.json"))
            require_skus(detail, product, league_group, {lane})
            if league_lanes[product_id] != {lane} and not (product_id == 702297 and not league_lanes[product_id]):
                raise ValueError(f"League finish conflicts for {product_id}")
            description = detail["customAttributes"].get("description") or ""
            if year in (2005, 2006) and str(year) not in description:
                raise ValueError(f"League copyright evidence differs for {product_id}")
            if year == 2009 and product_id != 153248 and "Crosshatched foiling" not in description:
                raise ValueError(f"League crosshatch evidence differs for {product_id}")
            image = f"{product_id}.jpg"
            bound(f"league-details/{image}")
            observed = league[image]
            header = ["ENEROY"] if product_id == 153246 else ["ENERGY"]
            years = set(re.findall(r"20\d{2}", " ".join(observed["footer"] + observed["scanner"])))
            if observed["header"] != header or years - {str(year)}:
                raise ValueError(f"League artwork conflicts for {product_id}")
            saw_year |= str(year) in years
            cards.append({"providerID": f"tcgplayer:{product_id}", "localID": str(product_id), "name": name,
                          "finishProducts": {finish: product_id}})
        if not saw_year:
            raise ValueError(f"The {year} League capture has no readable copyright control")
        families.append({"providerSetID": f"tcgplayer:{league_group}:{year}", "setName": f"{year} Basic Energy ({label})",
                         "setCode": "Energy", "year": year, "officialCount": 0, "cards": cards})

    for set_id, set_name, set_code, year, group, suffix in FAMILIES:
        provider = json.loads(bound(f"tcgdex-sets-{set_id}.json"))
        if provider["id"] != set_id or provider["name"] != set_name or provider["cardCount"]["official"] < 1:
            raise ValueError(f"Provider set identity differs for {set_id}")
        provider_cards = {row["id"]: row for row in provider["cards"]}
        rows, lanes = market(group)
        names = ENERGY_NAMES[:8] if year == 2022 else ENERGY_NAMES
        products = exact_products(rows, year, suffix, names)
        cards = []
        for index, name in enumerate(names, 164):
            product = products[name]
            product_id = product["productId"]
            if lanes[product_id] != ORDINARY_LANES:
                raise ValueError(f"Ordinary finish lanes differ for {product_id}")
            finish_products = {"normal": product_id, "reverse": product_id}
            if year == 2017:
                local_id = str(index)
                card_id = f"{set_id}-{local_id}"
                row = provider_cards[card_id]
                retained = legacy["cards"][card_id]
                if (row["name"] != name or row["localId"] != local_id or retained.get("isUnnumbered") is not True
                        or set(retained["minimum"]) != {"normal", "reverse"}):
                    raise ValueError(f"Existing Energy identity differs for {card_id}")
                wave_product = wave[name]
                wave_id = wave_product["productId"]
                if not wave_lanes[wave_id] <= {"Reverse Holofoil"}:
                    raise ValueError(f"Unexpected Wave Foil lane for {wave_id}")
                require_skus(json.loads(bound(f"details/{wave_id}.json")), wave_product, wave_group, {"Reverse Holofoil"})
                finish_products["wave"] = wave_id
                image = f"{local_id}.png"
                bound(f"2017/{image}")
            else:
                if any(row["name"].removeprefix("Basic ") == name for row in provider_cards.values()):
                    raise ValueError(f"Review provider backfill before adding {name} to {set_id}")
                require_skus(json.loads(bound(f"details/{product_id}.json")), product, group, ORDINARY_LANES)
                card_id, local_id = f"tcgplayer:{product_id}", str(product_id)
                image = f"{product_id}.jpg"
                bound(f"details/{image}")
            observed = (brilliant if year == 2022 else readings)[image]
            footer = f"©{year} Pokémon"
            if year in (2020, 2022):
                footer += " / Nintendo / Creatures / GAME FREAK"
            region = "scanner" if year == 2022 else "footer"
            if observed["header"] != ["ENERGY"] or observed[region] != [footer]:
                raise ValueError(f"Image does not show the reviewed unnumbered footer for {card_id}")
            cards.append({"providerID": card_id, "localID": local_id, "name": name,
                          "finishProducts": finish_products})
        if year == 2022:
            # This design is shared across releases. The market group provides
            # the product handles and does not assign pack checklist membership.
            families.append({"providerSetID": f"tcgplayer:{group}:{year}", "setName": "2022 Basic Energy (Sword & Shield)",
                             "setCode": "Energy", "year": year, "officialCount": 0, "cards": cards})
        else:
            families.append({"providerSetID": set_id, "setName": set_name, "setCode": set_code, "year": year,
                             "officialCount": provider["cardCount"]["official"], "cards": cards})
    return {"schemaVersion": 1, "marketBuild": start.decode().strip(), "families": families,
            "sourceSHA256": dict(sorted(sources.items()))}


def require_stable_identities(previous, current):
    def identities(table):
        return {(family["providerSetID"], card["name"]): (card["providerID"], card["localID"])
                for family in table["families"] for card in family["cards"]}

    old, new = identities(previous), identities(current)
    if changed := sorted(key for key, identity in old.items() if new.get(key) != identity):
        raise ValueError(f"Review the existing Energy ownership identities before replacing {changed}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", required=True, type=Path)
    parser.add_argument("--legacy-evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = derive(args.capture, read_json(args.legacy_evidence))
    if args.output.is_file():
        require_stable_identities(read_json(args.output), result)
    write_json(args.output, result)
    print(f"Reviewed {sum(len(family['cards']) for family in result['families'])} unnumbered Energy identities")


if __name__ == "__main__":
    main()
