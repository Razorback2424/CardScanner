#!/usr/bin/env python3
"""Build the scanner's ambiguous Magic footer families from pinned Scryfall inputs.

Use a Default Cards JSONL (optionally gzip-compressed), the /sets response,
and the bulk capture's UTC date. Run with --check to replay the bundled bytes.
An exact provider ID stays the printing identity, including after selection.
"""
import argparse
from collections import defaultdict
from datetime import date
import gzip
import hashlib
import json
from pathlib import Path
import re
import uuid


MODERN_START = "2014-07-18"
EXCLUDED_SETS = {"token", "memorabilia", "minigame", "art_series"}
EXCLUDED_LAYOUTS = {"token", "double_faced_token", "emblem", "art_series", "vanguard", "scheme", "planar", "augment", "host"}
FINISHES = {"nonfoil", "foil", "etched"}
# These serialized cohorts print the base collector number in the modern footer.
# The provider's z suffix represents the serial stamp elsewhere on the card.
SERIALIZED_FOOTER_SETS = {"acr", "ltc", "ltr", "mh3", "mkm", "mul", "who"}
# The four Kuja pairs share their printed numbers and differ on the reverse.
# These observations were checked against the eight exact Scryfall images.
REVIEWED_REVERSE_LABELS = {
    "008782d2-72b0-4554-b1ce-2db99969a4d8": "Back says Flare Star",
    "903192c7-f4ee-4872-aa61-3f8bdf2ab5c6": "Back says Flame Star",
    "374877d1-167a-42ea-adf3-a707ea0300e8": "Back says Flare Star",
    "b058d305-d032-47c9-8567-11a4b4319695": "Back says Flame Star",
    "98067c9a-d81e-4f5c-b55a-28872331fce8": "Back says Flare Star",
    "cdb5acf7-2878-466d-8224-24fa64a602f5": "Back says Flame Star",
    "d673228a-eec8-4f6e-82fd-10db909ccee2": "Back says Flare Star",
    "65530632-5b09-4359-921b-a6d094937aff": "Back says Flame Star",
}


def artwork(card):
    return tuple(face.get("illustration_id") for face in card["card_faces"]) if card.get("card_faces") else (card.get("illustration_id"),)


def printings(path, through):
    checksum = hashlib.sha256()
    cards = {}
    keys = ("id", "oracle_id", "set", "collector_number", "layout", "released_at", "frame", "border_color",
            "variation_of", "flavor_text")
    open_input = gzip.open if path.suffix == ".gz" else open
    with open_input(path, "rb") as source:
        for line in source:
            checksum.update(line)
            if not line.strip():
                continue
            card = json.loads(line)
            finishes = card.get("finishes", [])
            if (card.get("object") != "card" or card.get("lang") != "en" or card.get("digital")
                    or "paper" not in card.get("games", []) or card.get("oversized") is not False
                    or not card.get("layout") or card["layout"] in EXCLUDED_LAYOUTS or not card.get("oracle_id")
                    or not MODERN_START <= card.get("released_at", "") <= through
                    or not finishes or set(finishes) - FINISHES or len(finishes) != len(set(finishes))):
                continue
            identity = str(uuid.UUID(card["id"]))
            if identity in cards:
                raise ValueError(f"Duplicate paper printing {identity}")
            cards[identity] = {key: card.get(key) for key in keys}
            cards[identity]["artwork"] = artwork(card)
            cards[identity]["face_images"] = tuple((face.get("image_uris") or {}).get("normal", "").split("?")[0]
                                                   for face in card.get("card_faces", []))
            cards[identity]["promo_types"] = set(card.get("promo_types", []))
    return cards, checksum.hexdigest()


def footer_key(card):
    return card["set"].lower() + "/" + card["collector_number"].lower()


def same_design(a, b):
    return (all(a["artwork"]) and all(a[key] == b[key] for key in ("artwork", "layout", "frame", "border_color")))


def family_index(cards, sets):
    by_footer = {}
    for card in cards.values():
        key = footer_key(card)
        if key in by_footer:
            raise ValueError(f"Duplicate provider footer {key}")
        by_footer[key] = card

    families = defaultdict(dict)
    for card in cards.values():
        code, number = card["set"], card["collector_number"].lower()
        parent = sets[code].get("parent_set_code")
        base, label, reverse = None, None, False
        if code == "plst" and "-" in number:
            original_set, original_number = number.split("-", 1)
            base = by_footer.get(f"{original_set}/{original_number}")
            label = "The List · Planeswalker stamp"
        elif parent and (match := re.fullmatch(r"([0-9]+)[a-z]", number)):
            tags = card["promo_types"]
            if {"prerelease", "datestamped"} <= tags:
                label = "Prerelease date stamp"
            elif {"promopack", "stamped"} <= tags:
                label = "Promo Pack stamp"
            elif code == "pafr" and {"embossed", "instore"} <= tags:
                # Wizards' WPN Premium series overlays the base printing with a glossy ampersand.
                label = "D&D ampersand foil"
            if label:
                base = by_footer.get(f"{parent}/{match[1]}")

        if base and not same_design(card, base):
            base = None
        if (code in SERIALIZED_FOOTER_SETS and "serialized" in card["promo_types"]
                and (serialized := re.fullmatch(r"([0-9]+)z", number))):
            base = by_footer.get(f"{code}/{serialized[1]}")
            label = "Numbered serial stamp"
        variant_of = cards.get(card["variation_of"])
        if variant_of and variant_of["set"] == code and re.fullmatch(
                re.escape(variant_of["collector_number"].lower()) + r"†[a-z]?", number):
            base = variant_of
            label = "Printing variation"
            faces = card["face_images"]
            base_faces = base["face_images"]
            reverse = (len(faces) == len(base_faces) == 2 and all(faces) and all(base_faces)
                       and faces[0] == base_faces[0] and faces[1] != base_faces[1])

        if not base or not label or base["oracle_id"] != card["oracle_id"]:
            continue
        base_set = sets[base["set"]]
        if (base_set.get("set_type") in EXCLUDED_SETS or (base_set.get("released_at") or "") < MODERN_START
                or not re.fullmatch(r"[a-z0-9]{3,4}", base["set"])
                or not re.fullmatch(r"(?:[0-9]{1,4}[a-z★]?|★)", base["collector_number"].lower())):
            continue
        family = families[footer_key(base)]
        family[base["id"]] = (base, "Original printing", reverse or family.get(base["id"], (None, None, False))[2])
        family[card["id"]] = (card, label, reverse)

    result = {}
    for key, family in sorted(families.items()):
        original = by_footer[key]
        members = []
        for card, label, reverse in sorted(family.values(), key=lambda member: (member[0] != original, footer_key(member[0]))):
            # Some same-art variants can be selected by their printed clue.
            clue = re.match(r"^Entry [0-9]+:", card.get("flavor_text") or "")
            label = REVIEWED_REVERSE_LABELS.get(card["id"], clue[0].rstrip(":") if clue else label)
            member = {"id": card["id"], "setCode": card["set"], "collectorNumber": card["collector_number"], "label": label}
            if reverse or card["id"] in REVIEWED_REVERSE_LABELS:
                member["useReverse"] = True
            members.append(member)
        if len(members) > 75:
            raise ValueError(f"Footer family exceeds Scryfall batch limit: {key}")
        result[key] = {"oracleID": str(uuid.UUID(original["oracle_id"])), "members": members}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bulk", type=Path, required=True)
    parser.add_argument("--sets", type=Path, required=True)
    parser.add_argument("--through", type=lambda value: date.fromisoformat(value).isoformat(), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sets_bytes = args.sets.read_bytes()
    sets = {row["code"]: row for row in json.loads(sets_bytes)["data"]}
    cards, checksum = printings(args.bulk, args.through)
    families = family_index(cards, sets)
    metadata = {"schemaVersion": 1, "through": args.through, "sourceSHA256": checksum,
                "directorySHA256": hashlib.sha256(sets_bytes).hexdigest()}
    rows = [f"    {json.dumps(key, ensure_ascii=False)}: {json.dumps(value, ensure_ascii=False, separators=(',', ':'))}"
            for key, value in families.items()]
    artifact = json.dumps(metadata, indent=2)[:-2] + ',\n  "families": {\n' + ",\n".join(rows) + "\n  }\n}\n"
    if args.check:
        if args.output.read_text(encoding="utf-8") != artifact:
            parser.exit(1, "Magic printing family artifact differs from pinned inputs.\n")
    else:
        args.output.write_text(artifact, encoding="utf-8")
    print(f"{len(cards)} released paper printings checked, {len(families)} ambiguous footer families")


if __name__ == "__main__":
    main()
