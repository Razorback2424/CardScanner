"""Project documented English TCG printings from retained checklists."""
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
    (-17, "wgrt-eu", "WGRT", "War of the Giants Reinforcements", 104),
    (-18, "ys15-eu", "YS15", "2-Player Starter Deck: Yuya & Declan", 42),
    (-19, "ydb1-eu", "YDB1", "Yu-Gi-Oh! GX Card Almanac promotional cards", 3),
    (-20, "dl2-english", "DL2", "Duelist League Series 2 participation cards", 2),
    (-21, "wq11-english", "WQ11", "Yu-Gi-Oh! World Championship Qualifier National Championships 2011 prize cards", 3),
    (-22, "tyl-english", "TYL", "Make-A-Wish Foundation promotional card", 1),
    (-23, "jmp-se-2004-eu", "JMP", "Swedish Shonen Jump 2004, Issue 2 promotional card", 1),
    (-24, "jmp-se-2005-eu", "JMP", "Swedish Shonen Jump 2005, Issue 12 promotional card", 1),
    (-25, "world-championship-2004-english", "WCS", "Yu-Gi-Oh! World Championship 2004 prize cards", 2),
    (-26, "world-championship-2005-english", "WCS", "Yu-Gi-Oh! World Championship 2005 prize cards", 2),
    (-27, "world-championship-2017-english", "2017", "Yu-Gi-Oh! World Championship 2017 prize cards", 2),
    (-28, "world-championship-2018-english", "2018", "Yu-Gi-Oh! World Championship 2018 prize cards", 2),
    (2197, None, "MF03", "Mattel Action Figure promotional cards: Series 3", 1),
)

ENGLISH_NUMBERS = {
    "WGRT": r"WGRT-EN[0-9]{3}",
    "YS15": r"YS15-EN[DY][0-9]{2}",
    "YDB1": r"YDB1-EN00[1-3]",
    "DL2": r"DL2-EN00[12]",
    "WQ11": r"WQ11-EN00[1-3]",
    "TYL": r"TYL-EN001",
    "JMP": r"JMP-EN00[12]",
    "WCS": r"WCS-EN[45]0[12]",
    "2017": r"2017-EN00[12]",
    "2018": r"2018-EN00[12]",
    "MF03": r"MF03-EN001",
}

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
            prefix = code.split("-", 1)[0]
            pattern = ENGLISH_NUMBERS.get(prefix, r"[A-Z0-9]{2,4}-E[0-9]{3}")
            if re.fullmatch(pattern, code):
                rarity = entry["set_rarity"]
                if rarity in ("Short Print", "Super Short Print"):
                    rarity = "Common"
                elif rarity == "Extra Secret":
                    rarity = "Extra Secret Rare"
                key = (prefix, entry["set_name"])
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
            "name": title + (" (European English)" if release_id and release_id.endswith("-eu") else ""), "rows": rows,
            **({"suffix": "EN"} if prefix in ENGLISH_NUMBERS else {}),
            **({"galleryRegion": "EN"} if release_id and release_id.endswith("-english") else {}),
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
