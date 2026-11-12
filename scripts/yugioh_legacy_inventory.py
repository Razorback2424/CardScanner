"""Project numbered regional English TCG printings from retained checklists."""
import argparse
import collections
import hashlib
import json
import pathlib
import re

from yugioh_edition_galleries import RARITIES, gallery_rows
from yugioh_official_inventory import norm

# Permanent release IDs for groups with no existing marketplace group.
# Magic Ruler already mixes the two regional checklists in group 249.
RELEASES = (
    (-1, "lob-eu", "LOB", "Legend of Blue Eyes White Dragon", 103),
    (-2, "mrd-eu", "MRD", "Metal Raiders", 144),
    (-3, "psv-eu", "PSV", "Pharaoh's Servant", 105),
    (-4, "lon-eu", "LON", "Labyrinth of Nightmare", 105),
    (249, None, "MRL", "Magic Ruler", 131),
    (-6, "sdy-eu", "SDY", "Starter Deck: Yugi", 46),
    (-7, "sdk-eu", "SDK", "Starter Deck: Kaiba", 46),
    (-8, "tp1-eu", "TP1", "Tournament Pack: 1st Season", 30),
    (-9, "pcy-eu", "PCY", "Yu-Gi-Oh! Power of Chaos: Yugi the Destiny promotional cards", 4),
    (-10, "pcy-limited-eu", "PCY", "Yu-Gi-Oh! Power of Chaos: Yugi the Destiny Limited Collector's Edition", 1),
    (-11, "pck-eu", "PCK", "Yu-Gi-Oh! Power of Chaos: Kaiba the Revenge promotional cards", 3),
    (-12, "dor-eu", "DOR", "Yu-Gi-Oh! The Duelists of the Roses promotional cards", 3),
    (-13, "dl1-eu", "DL1", "Duelist League Series 1 participation cards", 2),
)

AUSTRALIAN_RELEASES = (
    (-14, "lob-au", "LOB", "Legend of Blue Eyes White Dragon", 126),
    (-15, "sdy-au", "SDY", "Starter Deck: Yugi", 50),
    (-16, "sdk-au", "SDK", "Starter Deck: Kaiba", 50),
)


def australian_releases(cards, captures):
    pages = {page["title"]: page for raw in captures for page in json.loads(raw)["query"]["pages"] if "missing" not in page}
    by_name = collections.defaultdict(list)
    for card in cards:
        by_name[norm(card["name"])].append(card)
    for group, release_id, prefix, title, count in AUSTRALIAN_RELEASES:
        revision, = pages[f"Set Card Lists:{title} (TCG-AU)"]["revisions"]
        content = revision["slots"]["main"]["content"]
        block = re.search(r"\{\{Set list\|region=AU([^\n]*)\n(.*?)\n\}\}", content, re.S)
        assert block, f"missing Australian checklist {title}"
        default = re.search(r"\|rarities=([^|]+)", block[1])
        rows = []
        for code, name, *rarities in gallery_rows(block[2]):
            assert code.startswith(prefix + "-A") and len(rarities) <= 1
            assert rarities or default, f"missing rarity for {code}"
            rarity = rarities[0] if rarities else default[1]
            rarity = RARITIES.get(rarity, rarity)
            candidates = by_name[norm(name)]
            if len(candidates) > 1:
                unmarked = code.replace("-A", "-", 1)
                candidates = [card for card in candidates if any(
                    row["set_code"] == unmarked and row["set_rarity"] == rarity for row in card.get("card_sets", []))]
            assert len(candidates) == 1, f"ambiguous Australian card {code}: {name}"
            rows.append([code, candidates[0]["id"], name, rarity])
        assert len({row[0] for row in rows}) == len(rows) == count, f"review the revised {title} checklist"
        yield {"groupID": group, "referenceID": release_id, "code": prefix, "suffix": "A",
               "name": title + " (Australian English)", "rows": sorted(rows),
               "source": f"https://yugipedia.com/index.php?oldid={revision['revid']}",
               "sourceSHA256": hashlib.sha256(content.encode()).hexdigest()}


def project(raw, australian_captures=()):
    cards = json.loads(raw)["data"]
    inventory = {}
    for card in cards:
        for entry in card.get("card_sets", []):
            code = entry["set_code"]
            if re.fullmatch(r"[A-Z0-9]{2,4}-E[0-9]{3}", code):
                rarity = entry["set_rarity"]
                if rarity in ("Short Print", "Super Short Print"):
                    rarity = "Common"
                key = (code.split("-")[0], entry["set_name"])
                inventory.setdefault(key, set()).add((code, card["id"], card["name"], rarity))
    releases = []
    all_codes = set()
    for group, release_id, prefix, title, count in RELEASES:
        rows = sorted(inventory[(prefix, title)])
        codes = {row[0] for row in rows}
        assert len(codes) == len(rows) == count and all_codes.isdisjoint(codes), f"review the revised {prefix} checklist"
        all_codes.update(codes)
        releases.append({
            "groupID": group, "referenceID": release_id, "code": prefix,
            "name": title + (" (European English)" if release_id else ""), "rows": rows,
        })
    if australian_captures:
        releases.extend(australian_releases(cards, australian_captures))
    return {"url": "https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes",
            "sha256": hashlib.sha256(raw).hexdigest(), "releases": releases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--australian-capture", type=pathlib.Path, action="append", default=[])
    args = parser.parse_args()
    output = project(args.input.read_bytes(), [path.read_bytes() for path in args.australian_capture])
    args.output.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")
