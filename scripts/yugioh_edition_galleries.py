"""Project explicit English editions from retained gallery revisions."""

import argparse
import collections
import datetime
import hashlib
import json
from pathlib import Path
import re

from yugioh_official_inventory import norm


EDITIONS = {"1E": "1st Edition", "UE": "Unlimited", "LE": "Limited"}
RARITIES = {"C": "Common", "SP": "Common", "SSP": "Common", "R": "Rare",
            "SR": "Super Rare", "UR": "Ultra Rare", "ScR": "Secret Rare", "PScR": "Prismatic Secret Rare",
            "UtR": "Ultimate Rare", "GMR": "Grand Master Rare", "URPR": "Ultra Pharaoh's Rare",
            "NPR": "Normal Parallel Rare",
            "DNPR": "Duel Terminal Normal Parallel Rare", "DRPR": "Duel Terminal Rare Parallel Rare",
            "DSPR": "Duel Terminal Super Parallel Rare", "DUPR": "Duel Terminal Ultra Parallel Rare",
            "Short Print": "Common", "Super Short Print": "Common"}
GALLERY = re.compile(r"\{\{(Set gallery|Card gallery)\|([^\n]*)\n(.*?)\n\}\}", re.S)

# The marketplace combines some independently named distributions in one group.
MARKET_RELEASES = {
    155: r"champion pack game seven",
    175: r"yu gi oh the dawn of destiny promotional cards",
    179: r"duel terminal preview wave [12]",
    182: r"duelist league \d+ participation cards",
    279: r"shonen jump championship 20\d{2} prize card(?: [ab])?",
    280: r"shonen jump championship 20\d{2} prize card(?: [ab])?",
    333: r"tournament pack 1st season",
    351: r"yu gi oh world championship 200[67] prize cards",
    1347: r"yu gi oh championship series 20\d{2} prize cards?",
    1660: r"dimension of chaos special edition",
    1921: r"yu gi oh the sacred cards promotional cards",
    2197: r"mattel action figure promotional cards series 3",
    2215: r"pharaoh tour 200[567] (?:final prize card|promotional cards)",
}
WINNER_STAMP_SOURCE = "https://www.yugioh-card.com/en/products/up01/"
WINNER_STAMPS = {"OTS Stamp", "Regional Qualifier Stamp", "Judge Stamp"}
EDITION_IDS = {"1E": "yugioh1stEdition", "UE": "yugiohUnlimited", "LE": "yugiohLimited"}
MARKET_EDITION_IDS = {**EDITION_IDS, "DT": "yugiohLimited"}
TERMINAL_GROUPS = {179, *range(1327, 1334)}


def inventory_hash(inventory):
    content = json.dumps(inventory, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(content.encode()).hexdigest()


def gallery_rows(block):
    for line in block.splitlines():
        fields = [value.strip() for value in line.split("//", 1)[0].split(";")]
        if len(fields) > 1 and re.fullmatch(r"[A-Z0-9]{2,4}-(?:[EA][0-9]{3}|EN[A-Z0-9]{3})", fields[0]):
            yield fields


def project(inventory, captures):
    """Use exact numbered entries from explicitly scoped edition galleries."""
    titles = {}
    by_code = {}
    for release in inventory["releases"]:
        region = release.get("galleryRegion", "AU" if release.get("suffix") == "A" else "EU")
        title = release["name"].removesuffix(" (European English)").removesuffix(" (Australian English)")
        if title == "Magic Ruler":
            title = "Spell Ruler"
        titles[(region, title)] = release["groupID"]
        for code, _, name, rarity in release["rows"]:
            assert code not in by_code, f"duplicate regional inventory code {code}"
            by_code[code] = (release["groupID"], title, norm(name), rarity, region)

    sources, supplements = [], []
    for raw, captured_at in captures:
        assert datetime.datetime.fromisoformat(captured_at).utcoffset() == datetime.timedelta(0)
        for page in json.loads(raw)["query"]["pages"]:
            if "missing" in page:
                continue
            title = page["title"]
            revision, = page["revisions"]
            content = revision["slots"]["main"]["content"]
            receipt = {"url": f"https://yugipedia.com/index.php?oldid={revision['revid']}",
                       "sha256": hashlib.sha256(content.encode()).hexdigest(), "capturedAt": captured_at}
            if match := re.fullmatch(r"Set Card Galleries:(.*) \(TCG-(EN|EU|AU)-(1E|UE|LE)\)", title):
                release, region, edition = match.groups()
                group = titles.get((region, release))
                if group is None:
                    continue
                galleries = [gallery for gallery in GALLERY.finditer(content) if gallery[1] == "Set gallery"]
                assert galleries, f"missing edition inventory {title}"
                rows = collections.defaultdict(set)
                for gallery in galleries:
                    default = re.search(r"(?:^|\|)rarity=([^|]+)", gallery[2])
                    for code, name, *rarities in gallery_rows(gallery[3]):
                        # The two UK half-decks also repeat their code's letter as an image tag.
                        if code.startswith(("YS15-END", "YS15-ENY")) and len(rarities) == 2 and rarities[1] == code[-3]:
                            rarities.pop()
                        if len(rarities) > 1 or not (rarities or default):
                            continue
                        rarity = rarities[0] if rarities else default[1]
                        if code == "LOB-A070" and name == "Red-Eyes B. Dragon":
                            name = "Red-Eyes Black Dragon"
                        rows[code].add((norm(name), RARITIES.get(rarity, rarity)))
                codes = sorted(code for code, values in rows.items()
                               if code in by_code and by_code[code][0] == group and values == {by_code[code][2:4]})
                if codes:
                    sources.append({**receipt, "groupID": group, "edition": EDITIONS[edition], "codes": codes})
            elif title.startswith("Card Gallery:"):
                name = norm(title.removeprefix("Card Gallery:"))
                for gallery in GALLERY.finditer(content):
                    region = next((field[7:] for field in gallery[2].split("|") if field.startswith("region=")), "")
                    if gallery[1] != "Card gallery" or region not in ("EN", "EU", "AU"):
                        continue
                    for fields in gallery_rows(gallery[3]):
                        if len(fields) != 4 or fields[0] not in by_code or fields[3] not in EDITIONS:
                            continue
                        code, release, rarity, edition = fields
                        group, expected_release, expected_name, expected_rarity, expected_region = by_code[code]
                        # The published promo grouping includes Kuriboh from the collector's release.
                        collector_promo = code == "PCY-E005" and release == expected_release.removesuffix(
                            " promotional cards") + " Limited Collector's Edition"
                        if (region == expected_region and (release == expected_release or collector_promo) and name == expected_name
                                and RARITIES.get(rarity, rarity) == expected_rarity):
                            supplements.append({**receipt, "groupID": group, "edition": EDITIONS[edition], "codes": [code]})
    proved = {(code, source["edition"]) for source in sources for code in source["codes"]}
    for source in supplements:
        lane = (source["codes"][0], source["edition"])
        if lane not in proved:
            sources.append(source)
            proved.add(lane)
    return {"inventorySHA256": inventory_hash(inventory),
            "sources": sorted(sources, key=lambda row: (row["groupID"], row["edition"], row["codes"]))}


def project_market(catalog, captures):
    """Match individual finishes and stamps before authorizing an unpriced market product."""
    groups = {row["g"]: row for row in catalog["sets"]}
    targets = [row for row in catalog["printings"] if not row["e"] and not row["ir"]]
    codes = {row["c"] for row in targets}
    entries = collections.defaultdict(list)
    for raw, captured_at in captures:
        assert datetime.datetime.fromisoformat(captured_at).utcoffset() == datetime.timedelta(0)
        for page in json.loads(raw)["query"]["pages"]:
            title = page["title"]
            scope = re.fullmatch(r"Set Card Galleries:(.*) \(TCG-(EN|NA|EU|AU|OC)-(1E|UE|LE)\)", title)
            if "missing" in page or (scope is None and not title.startswith("Card Gallery:")):
                continue
            revision, = page["revisions"]
            content = revision["slots"]["main"]["content"]
            receipt = {"url": f"https://yugipedia.com/index.php?oldid={revision['revid']}",
                       "sha256": hashlib.sha256(content.encode()).hexdigest(), "capturedAt": captured_at}
            if scope is not None:
                release, region, edition = scope.groups()
                for gallery in GALLERY.finditer(content):
                    if gallery[1] != "Set gallery":
                        continue
                    default = re.search(r"(?:^|\|)rarity=([^|]+)", gallery[2])
                    for code, name, *fields in gallery_rows(gallery[3]):
                        if code not in codes or len(fields) > 2:
                            continue
                        rarity = (fields[0] if fields else "") or (default[1] if default else "")
                        variant = fields[1] if len(fields) == 2 else ""
                        if rarity and variant in ("", "EA"):
                            art = "extended art" if variant == "EA" else ""
                            entries[(code, norm(name))].append((norm(release), rarity, edition, region, art, receipt))
                continue
            name = norm(title.removeprefix("Card Gallery:"))
            for gallery in GALLERY.finditer(content):
                region = next((field[7:] for field in gallery[2].split("|") if field.startswith("region=")), "")
                if gallery[1] != "Card gallery" or region not in ("EN", "NA", "EU", "AU", "OC"):
                    continue
                for line in gallery[3].splitlines():
                    fields = [value.strip() for value in line.split("//", 1)[0].split(";")]
                    if len(fields) not in (4, 5) or fields[0] not in codes or fields[3] not in MARKET_EDITION_IDS:
                        continue
                    code, release, rarity, edition, *variants = fields
                    entries[(code, name)].append((norm(release), rarity, edition, region, norm(variants[0]) if variants else "", receipt))

    winner_stamps = collections.defaultdict(list)
    for row in catalog["printings"]:
        if row["g"] == 24789 and row["c"].startswith("WI26-EN") and row["r"] == "Ultra Rare":
            winner_stamps[row["c"]].append(row["art"])

    products = {}
    for row in targets:
        group = groups[row["g"]]
        name = norm(row.get("on") or catalog["cards"][row["k"]]["n"])
        title = norm(group["n"].removesuffix(" (Worldwide English)"))
        rarity = norm(row.get("vr", row["r"]))
        art = row["art"] or ""
        variant = "" if norm(RARITIES.get(art, art)) == rarity else norm(art)
        terminal = row["g"] in TERMINAL_GROUPS and row["c"].startswith(group["a"] + "-EN")
        proofs = {}
        for release, finish, edition, region, source_variant, receipt in entries[(row["c"], name)]:
            if (edition == "DT") != terminal:
                continue
            if release != title and not re.fullmatch(MARKET_RELEASES.get(row["g"], r"(?!)"), release):
                continue
            physical_rarity = norm(RARITIES.get(finish, finish))
            if physical_rarity != rarity and (row["g"], physical_rarity, rarity) != (2197, "normal parallel rare", "parallel rare"):
                continue
            if group["n"].endswith(" (Worldwide English)") and region != "EN":
                continue
            if variant == source_variant or (variant == "eu" and region == "EU" and not source_variant):
                proofs.setdefault(edition, receipt)
            elif (row["g"] == 24789 and edition == "UE" and not source_variant and art in WINNER_STAMPS
                    and len(winner_stamps[row["c"]]) == 3 and set(winner_stamps[row["c"]]) == WINNER_STAMPS):
                # Konami documents all three logo variants of the same 40-card release.
                proofs.setdefault(edition, {**receipt, "stampSource": WINNER_STAMP_SOURCE})
        if proofs:
            products[str(row["p"])] = {
                "printing": {"groupID": row["g"], "code": row["c"], "productName": row["pn"], "rarity": row["r"]},
                "editions": sorted(MARKET_EDITION_IDS[edition] for edition in proofs),
                "reviewedAt": max(proof["capturedAt"] for proof in proofs.values()),
                "evidence": {MARKET_EDITION_IDS[edition]: proofs[edition] for edition in sorted(proofs)},
            }
    return products


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path)
    parser.add_argument("existing_editions", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--market", action="store_true", help="Use the previous catalog in place of a reference inventory")
    parser.add_argument("--capture", action="append", required=True, metavar="UTC_TIMESTAMP=JSON_PATH")
    args = parser.parse_args()
    captures = []
    for capture in args.capture:
        timestamp, filename = capture.split("=", 1)
        captures.append((Path(filename).read_bytes(), timestamp))
    evidence = json.loads(args.existing_editions.read_bytes())
    inventory = json.loads(args.inventory.read_bytes())
    if args.market:
        evidence["products"].update(project_market(inventory, captures))
    else:
        evidence["galleryEvidence"] = project(inventory, captures)
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
