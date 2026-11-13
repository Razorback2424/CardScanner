#!/usr/bin/env python3
"""Build a deterministic English catalog with independently graded exact membership.

Positive provider evidence permits explicit selection under POLICY. It never
proves exhaustive physical coverage or printing-to-artwork correspondence.
"""
import argparse
import collections
import datetime
import hashlib
import json
import math
import os
import pathlib
import re
import time
import urllib.request
import uuid
import sys

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from yugioh_edition_galleries import inventory_hash
from yugioh_official_inventory import RULE as FAMILY_RULE, extract as extract_inventory, extract_release_calendar, norm
LANES = {"1st Edition": "yugioh1stEdition", "Unlimited": "yugiohUnlimited", "Limited": "yugiohLimited"}
RARITIES = set("UR SR SCR SE UTR ULR PUR PCR PSR QCSR QCR GR STR CR R C SP SSP MSR ESR GSR PGR".split())
# Exact numbered releases from the Konami redemption program.
REDEMPTION_CODES = ("EEN-EN015K", "EOJ-EN004K", "MDP2-EN001K", "MDP2-EN002K", "MDP2-EN004K",
                    "MDP2-EN005K", "MDP2-EN006K", "POTD-EN031K", "TLM-EN035K")
CODE = re.compile(r"^(?:[A-Z0-9]{2,4}-(?:(?:EN|E)[A-Z0-9]{3}|[0-9]{3})|IOC-SE[1-4]|(?:LOB|SDY|SDK)-A[0-9]{3}|"
                  + "|".join(REDEMPTION_CODES) + ")$")
POLICY = "yugioh-provider-membership-v1-2026-10-21"
INVALID_RARITIES = {"new", "2", "3", "new artwork"}
PRICE_FIELDS = ("marketPrice", "lowPrice", "midPrice", "highPrice", "directLowPrice")
PACKAGING_NAME = re.compile(
    r"\b(?:booster (?:box|pack|case)|blister|starter deck|structure deck|playmat|sleeves|binder|sealed|"
    r"collector.?s? tins?|collection tin|anniversary tin|tin of|egyptian god deck|ingot set|"
    r"(?:special|deluxe|super|advance|advanced) edition|(?:mini[- ]|tuck |value )box|"
    r"mega[- ](?:pack|tin)|portfolio|gameboard edition|collector.?s? set|box set)\b"
    r"|\b(?:tin|display|box|pack|case|bundle|deck|briefcase|starter set)(?: \[[^\]]+\]| \([^()]*\)| - Set of \d+)*$"
    r"|\b(?:Astral Pack \d+|Speed Duel: Tournament Pack \d+|Elemental Hero Collection [12]|Duel Master['’]s Guide)$"
    r"|^(?:Primal Origin -Plus-|Stainless Steel Egyptian God Cards)$",
    re.I,
)
CORRESPONDENCE_RULES = json.loads((ROOT / 'yugioh_correspondence_rules.json').read_text())


def excluded_product_reason(product, foreign):
    ext = {field["name"]: field["value"] for field in product.get("extendedData", [])}
    code = ext.get("Number", "").strip().upper()
    name = product["name"]
    if foreign:
        return code, "foreignLanguage"
    if not code:
        if "This card is only printed in Japanese" in ext.get("Description", ""):
            return code, "foreignLanguage"
        if ext.get("Card Type") == "Field Center" or (
                product.get("groupId") == 1322 and name.startswith("Field Center Token: ") and ext.keys() <= {"Rarity", "Description"}):
            return code, "fieldCenterAccessory"
        if ext.keys() <= {"Description", "UPC"} and PACKAGING_NAME.search(name):
            return code, "sealedOrAccessoryName"
    return code, "missingPrintedIdentity"


def grade_prices(rows):
    """Exact product rows only. Identical repeats share this response's provenance."""
    by_lane = collections.defaultdict(list)
    for row in rows:
        by_lane[row.get("subTypeName")].append(row)
    evidence, reasons = [], []
    for lane, values in sorted(by_lane.items(), key=lambda x: str(x[0])):
        if lane not in LANES:
            reasons.append("unknownSubtype")
            continue
        if len({packed(x) for x in values}) != 1:
            reasons.append("conflictingDuplicate:" + LANES[lane])
            continue
        row = values[0]
        valid = lambda x: isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) and x >= 0
        if any(row.get(k) is not None and not valid(row[k]) for k in PRICE_FIELDS):
            reasons.append("invalidNumeric:" + LANES[lane])
            continue
        if not any(valid(row.get(k)) and row[k] > 0 for k in PRICE_FIELDS):
            reasons.append("candidateOnly:" + LANES[lane])
            continue
        market = row.get("marketPrice")
        evidence.append({"e": LANES[lane], "t": "providerMarket" if valid(market) and market > 0 else "providerListing",
                         "q": market if valid(market) else None})
    return evidence, reasons

def corresponding_rarity(gid, code, rarity):
    for rule in CORRESPONDENCE_RULES['rules']:
        if gid == rule['groupID'] and code.startswith(rule['codePrefix']):
            return rule['rarities'].get(rarity, rarity)
    return rarity

def stable(namespace, material):
    return str(uuid.UUID(bytes=hashlib.md5((namespace + material).encode()).digest(), version=3))

def packed(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def product_identity_digest(products):
    """Bind reviewed inventories to the product fields used for physical identity."""
    rows = [(p["productId"], p.get("categoryId"), p.get("groupId"), p["name"],
             sorted((x["name"], x["value"]) for x in p.get("extendedData", []) if x["name"] in ("Number", "Rarity")))
            for p in sorted(products, key=lambda p: p["productId"])]
    return hashlib.sha256(packed(rows)).hexdigest()


def reviewed_inventories(profiles, products, product_hashes, official_html):
    """Use checked-in review receipts when their covered product identity still agrees."""
    requested = set()
    for path in official_html:
        data = path.read_bytes()
        profile = next((p for p in profiles if p["sha256"] == hashlib.sha256(data).hexdigest()), None)
        assert profile is not None, "unreviewed official inventory capture"
        assert all(profile[k] == v for k, v in extract_inventory(data, profile).items()), "official inventory changed"
        requested.add(profile["groupID"])

    admitted = []
    for profile in profiles:
        gid = profile["groupID"]
        if gid not in products:
            continue
        if (profile["productsSHA256"] == product_hashes[gid]
                or profile.get("productIdentitySHA256") == product_identity_digest(products[gid])):
            admitted.append(profile)
    assert requested <= {profile["groupID"] for profile in admitted}, "product identity changed; review required"
    return admitted


def matching_releases(groups, release_calendar, reviewed_dates=None):
    official = collections.defaultdict(list)
    for release in release_calendar:
        if release["date"] != "1990-01-01":  # Placeholder in the Konami archive.
            official[norm(release["name"])].append(release)
    group_names = collections.Counter(norm(g["name"]) for g in groups)
    matches = {g["groupId"]: official[norm(g["name"])][0] for g in groups
               if group_names[norm(g["name"])] == 1 and len(official[norm(g["name"])]) == 1}
    by_id = {release["id"]: release for releases in official.values() for release in releases if "id" in release}
    for group in groups:
        gid = group["groupId"]
        review = scoped_release_date(reviewed_dates, gid, group["name"], group.get("abbreviation") or "")
        if not review:
            continue
        release_id = review.get("officialReleaseID")
        release = by_id.get(release_id) if release_id else matches.get(gid)
        if release and release["date"] == review["date"]:
            matches[gid] = release
        else:
            matches.pop(gid, None)
    return matches


def scoped_release_date(reviews, group_id, name, abbreviation):
    review = (reviews or {}).get(str(group_id))
    if review and (review["name"], review["abbreviation"]) == (name, abbreviation):
        date = datetime.date.fromisoformat(review["date"])
        assert date.isoformat() == review["date"] and date.year >= 2002, f"invalid release date {group_id}"
        assert review["source"].startswith("https://"), f"missing release date evidence {group_id}"
        return review
    return None


def release_checklist_targets(groups, calendar, reviewed_dates, supplemental_checklists):
    targets = {release["id"]: (gid, release)
               for gid, release in matching_releases(groups, calendar, reviewed_dates).items()}
    groups_by_id = {group["groupId"]: group for group in groups}
    for release in calendar:
        review = (supplemental_checklists or {}).get(release["id"])
        if not review or not (group := groups_by_id.get(review["groupID"])):
            continue
        if (group["name"], group.get("abbreviation") or "") != (review["name"], review["abbreviation"]):
            continue
        assert CODE.fullmatch(review["printingCode"]) and review["source"].startswith("https://")
        targets[release["id"]] = (review["groupID"], {**release, "printingCode": review["printingCode"]})
    return targets


def reviewed_reference_membership(inventory, evidence):
    printings = {code: (release["groupID"], name, rarity)
                 for release in inventory["releases"] for code, _, name, rarity in release["rows"]}
    memberships = collections.defaultdict(dict)

    def admit(code, edition, url, captured_at, source_hash=None):
        _, name, rarity = printings[code]
        receipt = {"url": url, "code": code, "name": name, "rarity": rarity, "edition": edition}
        if source_hash is not None:
            receipt["sourceSHA256"] = source_hash
        memberships[code].setdefault(edition, {"e": edition, "t": "independentlyReviewed", "q": None,
            "h": hashlib.sha256(packed(receipt)).hexdigest(), "s": captured_at, "st": "reviewedAt"})

    for source in evidence["sources"]:
        for code in source["firstEditionCodes"]:
            admit(code, LANES["1st Edition"], source["url"], evidence["capturedAt"])

    if gallery := evidence.get("galleryEvidence"):
        assert gallery["inventorySHA256"] == inventory_hash(inventory), "gallery evidence belongs to another inventory"
        for source in gallery["sources"]:
            assert re.fullmatch(r"https://yugipedia\.com/index\.php\?oldid=[1-9][0-9]*", source["url"])
            assert re.fullmatch(r"[a-f0-9]{64}", source["sha256"])
            for code in source["codes"]:
                assert code in printings and printings[code][0] == source["groupID"], f"gallery release mismatch {code}"
                admit(code, LANES[source["edition"]], source["url"], source["capturedAt"], source["sha256"])
    return memberships


def reference_printings(inventory, edition_evidence, rows, canonical, sets, previous_references, previous):
    """Retain a stable physical identity for documented printings without a market product."""
    if not inventory:
        return [], set()
    by_code = collections.defaultdict(list)
    for row in rows:
        by_code[row["c"]].append(row)
    reviewed = reviewed_reference_membership(inventory, edition_evidence)
    reference_rows, assigned_products = [], set()
    known_groups = {row["g"] for row in sets}
    marketplace_names = {row["g"]: norm(row["n"]) for row in sets}
    for release in inventory["releases"]:
        gid = release["groupID"]
        if reference_id := release["referenceID"]:
            assert gid not in known_groups and gid < 0, "reference group collision"
            sets.append({"g": gid, "n": release["name"], "a": release["code"] + "-" + release.get("suffix", "E"), "d": "",
                         "ref": reference_id, "sourceSHA256": release.get("sourceSHA256", inventory["sha256"])})
            known_groups.add(gid)
        else:
            assert gid in known_groups, "missing shared marketplace release"
        release_names = {norm(release["name"]), norm(release["name"].removesuffix(" (European English)").removesuffix(" (Australian English)"))}
        for code, source_id, name, rarity in release["rows"]:
            canonical_id = stable("yugioh-card:", "ygoprodeck:" + str(source_id))
            identity = stable("yugioh-reference-printing:", f"{gid}:{code}:{source_id}:{rarity}")
            prior = previous_references.get(identity)
            matching = [row for row in by_code[code] if not row["ir"]
                        and marketplace_names[row["g"]] in release_names
                        and row.get("vr", row["r"]) == rarity and row["art"] in (None, code)
                        and norm(canonical[row["k"]]["n"]) == norm(name)]
            if prior is None and len(matching) == 1:
                row = matching[0]
                if not row["ec"] and reviewed[code]:
                    membership = {**reviewed[code], **{m["e"]: m for m in row["m"]}}
                    row["e"] = sorted(membership)
                    row["m"] = [membership[e] for e in row["e"]]
                    row["ee"] = POLICY
                continue
            # A new exact product can attach to an already released reference.
            # Previously assigned marketplace UUIDs keep their original rows.
            linked = None
            if prior and len(matching) == 1:
                match = matching[0]
                if (match["pn"] == name and match["art"] is None and match["r"] == rarity
                        and (match["p"] == prior.get("p") or (prior.get("p") is None and match["p"] not in previous))):
                    linked = match
                    assigned_products.add(match["p"])
            canonical.setdefault(canonical_id, {"id": canonical_id, "n": name,
                "pc": [source_id] if 0 < source_id <= 99_999_999 else [], "sourceID": source_id, "imageIDs": []})
            retained = prior or {}
            membership = {m["e"]: {**m, "q": None} for m in retained.get("m", [])}
            membership.update(reviewed[code])
            if linked:
                for reason in linked["limitations"]:
                    if reason.startswith(("invalidNumeric:", "conflictingDuplicate:")):
                        edition = reason.split(":", 1)[1]
                        if membership.get(edition, {}).get("t") != "independentlyReviewed":
                            membership.pop(edition, None)
                membership.update({m["e"]: m for m in linked["m"]})
            market = ({"p": linked["p"], "pg": linked["g"]} if linked else
                      {key: retained[key] for key in ("p", "pg") if key in retained})
            reference_rows.append({"id": identity, "c": code, "g": gid, "k": canonical_id,
                "r": rarity, "art": None, "pn": name, "e": sorted(membership), "ec": False,
                "ee": POLICY if membership else None, "pe": linked["pe"] if linked else [],
                "img": linked["img"] if linked else retained.get("img"),
                "m": [membership[e] for e in sorted(membership)], "ir": None, "canonicalLink": "linked", **market})
    return reference_rows, assigned_products


def build(groups, products, prices, cards, aliases, reviews, captured_at, floor=10000, price_provenance=None,
          previous=None, taxonomy_scopes=None, printing_inventory=None, release_calendar=(), rarity_corrections=None,
          reference_inventory=None, reference_editions=None, previous_references=None, reviewed_dates=None,
          passcode_corrections=None):
    entries = collections.defaultdict(list)
    identity_entries = collections.defaultdict(set)
    names, by_id = {}, {}
    for card in cards:
        cid = card["id"]
        by_id[cid] = card
        names[cid] = {norm(card["name"])} | {norm(x["beta_name"]) for x in card.get("misc_info", []) if x.get("beta_name")} | {norm(x) for x in aliases.get(str(cid), [])}
        for row in card.get("card_sets", []):
            identity_entries[row['set_code']].add(cid)
            if row["set_rarity"].lower() in INVALID_RARITIES: continue
            entries[row["set_code"]].append((cid, row["set_name"], row["set_rarity"]))
    exceptions = collections.defaultdict(list)
    incomplete = collections.defaultdict(set)
    canonical, rows, sets = {}, [], []
    correspondence = {}
    release_matches = matching_releases(groups, release_calendar, reviewed_dates)
    display_cards = []
    for group in sorted(groups, key=lambda x: x["groupId"]):
        gid = group["groupId"]
        sets.append({"g": gid, "n": group["name"], "a": group.get("abbreviation") or "",
                     "d": release_matches.get(gid, {}).get("date", ""),
                     "created": group.get("publishedOn")})
        lanes = collections.defaultdict(set)
        product_prices = collections.defaultdict(list)
        for row in prices[gid]:
            lanes[row["productId"]].add(row["subTypeName"])
            product_prices[row["productId"]].append(row)
        for product in sorted(products[gid], key=lambda x: x["productId"]):
            pid = product["productId"]
            ext = {x["name"]: x["value"] for x in product.get("extendedData", [])}
            conflicting_fields = any(len({x['value'] for x in product.get('extendedData', []) if x['name'] == field}) > 1 for field in ('Number', 'Rarity'))
            code, rarity = ext.get("Number", "").strip().upper(), ext.get("Rarity", "").strip()
            prior = (previous or {}).get(pid)
            physical_rarity = None
            unverified_release = False
            correction = (rarity_corrections or {}).get(str(pid))
            if (correction and not conflicting_fields and product.get("categoryId") == 2
                    and product.get("groupId") == gid == correction["groupID"]
                    and code == correction["code"] and product["name"] == correction["productName"]
                    and rarity in (correction["providerRarity"], correction.get("physicalRarity"))):
                if correction.get("language") == "ja":
                    exceptions["foreignLanguage"].append(pid)
                    continue
                display_rarity = rarity or correction.get("physicalRarity")
                if not code and display_rarity and (display_id := correction.get("unnumberedDisplayCardID")) in by_id:
                    source = by_id[display_id]
                    card_id = stable("yugioh-card:", f"ygoprodeck:{display_id}")
                    canonical[card_id] = {"id": card_id, "n": source["name"], "pc": [display_id],
                        "sourceID": display_id, "imageIDs": [i["id"] for i in source.get("card_images", [])]}
                    display_cards.append({"id": stable("yugioh-printing:", f"tcgplayer:2:{pid}"),
                        "c": "", "g": gid, "k": card_id, "r": display_rarity, "art": None,
                        "p": pid, "pn": product["name"], "e": [], "ec": False, "ee": None, "pe": [],
                        "img": product.get("imageUrl"), "m": [], "ir": "unnumberedDisplay", "canonicalLink": "linked"})
                    continue
                physical_rarity = correction.get("physicalRarity")
                unverified_release = correction.get("unverifiedRelease") is True
                if prior and prior["r"] in (correction["providerRarity"], physical_rarity):
                    # A known provider correction keeps the admitted product binding.
                    rarity = prior["r"]
            unsupported_code = bool(code and not CODE.fullmatch(code))
            reason = "noNumber" if not code else "foreignLanguage" if re.search(r"-(?:JP|FR|DE|IT|SP|PT|KR|AE|CN)[0-9]", code) else "noRarity" if not rarity else None
            if reason:
                exceptions[reason].append(pid)
                if CODE.fullmatch(code): incomplete[code].add("skippedProduct")
                continue
            observed = sorted(LANES[x] for x in lanes[pid] if x in LANES)
            if lanes[pid] - LANES.keys():
                exceptions["unknownSubtype"].append(pid)
                incomplete[code].add("unknownSubtype")
            if not observed: exceptions["noEditionLane"].append(pid)
            name, art = product["name"], []
            while (match := re.search(r"\s*\(([^()]*)\)\s*$", name)):
                suffix = match[1]
                name = name[:match.start()].strip()
                if suffix.upper() not in RARITIES and suffix.lower() != rarity.lower(): art.insert(0, suffix)
            matches = {cid for cid in identity_entries[code] if norm(name) in names[cid]}
            cid = next(iter(matches)) if len(matches) == 1 else None
            same_prior_product = prior and (prior["g"], prior["c"], prior["r"], prior["pn"]) == (gid, code, rarity, product["name"])
            valid_market_binding = not conflicting_fields and product.get("categoryId") == 2 and product.get("groupId") == gid
            retained_card = None
            if not identity_entries[code] and same_prior_product and prior.get("canonicalLink") == "linked" and valid_market_binding:
                # An omitted secondary row cannot invalidate a previously linked exact product.
                if retained_card := prior.get("priorCanonical"):
                    cid = retained_card["sourceID"]
                    exceptions["retainedCanonicalLink"].append(pid)
            # Some exact marketplace titles omit the printed stars entirely.
            # Recover the name only when the release, code, rarity and full
            # title after star elision identify one secondary record.
            official_name = None
            if not matches and valid_market_binding:
                symbol_matches = {candidate for candidate, release, finish in entries[code]
                    if norm(release) == norm(group["name"]) and norm(finish) == norm(physical_rarity or rarity)
                    and ("★" in by_id[candidate]["name"] or "☆" in by_id[candidate]["name"])
                    and norm(by_id[candidate]["name"].replace("★", "").replace("☆", "")) == norm(name)}
                if len(symbol_matches) == 1:
                    official_name = by_id[next(iter(symbol_matches))]["name"]
            key = "ygoprodeck:" + str(cid) if cid is not None else "name:" + norm(name)
            card_id = retained_card["id"] if retained_card else stable("yugioh-card:", key)
            source = by_id.get(cid, {})
            if retained_card and not source:
                canonical.setdefault(card_id, dict(retained_card))
            else:
                canonical[card_id] = {"id": card_id, "n": source.get("name", name),
                    "pc": [cid] if cid is not None and 0 < cid <= 99999999 else [],
                    "sourceID": cid, "imageIDs": [i["id"] for i in source.get("card_images", [])]}
            if cid is None: incomplete[code].add("nameMismatch")
            elif norm(name) != norm(canonical[card_id]["n"]): exceptions["aliasMatch"].append(pid)
            review = None if unverified_release else reviews.get(str(pid))
            if review and (binding := review.get("printing")) is not None and binding != {
                    "groupID": gid, "code": code, "productName": product["name"], "rarity": rarity}:
                exceptions["printingEditionEvidenceDrift"].append(pid)
                review = None
            membership, membership_reasons = grade_prices(product_prices[pid])
            editions, complete, evidence = [], False, None
            rejected = set(LANES.values()) if unverified_release else set()
            if review:
                assert review.get("evidence") and set(review["editions"]) <= set(LANES.values()) and review["editions"]
                editions = sorted(set(review["editions"]))
                complete, evidence = review.get("complete") is True, review["evidence"]
                rejected = set(review.get("rejectProviderEditions", []))
                if rejected:
                    assert (review.get("printing") and isinstance(evidence, dict) and set(editions) <= evidence.keys()
                            and rejected <= set(LANES.values()) - set(editions)), f"unbound edition correction {pid}"
                if complete:
                    assert {m['e'] for m in membership} <= set(editions) | rejected, f"review/price contradiction {pid}"
            if not complete: exceptions["physicalCoverageUnknown"].append(pid)
            blocked = {r.split(':', 1)[1] for r in membership_reasons if r.startswith(('conflictingDuplicate:', 'invalidNumeric:'))}
            provenance = (price_provenance or {}).get(gid, {})
            for m in membership: m.update(provenance)
            if review:
                for edition in editions:
                    if edition not in {m['e'] for m in membership}:
                        membership.append({'e':edition, 't':'independentlyReviewed', 'q':None,
                            'h':hashlib.sha256(packed(review)).hexdigest(), 's':review.get('reviewedAt', captured_at), 'st':'reviewedAt'})
            # Historical support survives absence, but explicit conflicting rows
            # retract only their affected lane. No edition transfer across products.
            if same_prior_product:
                for m in prior.get("m", []):
                    if m["e"] not in {x["e"] for x in membership} | blocked and m.get("h") and m.get("s"):
                        membership.append({**m, "q": None})
            contradicted = [m for m in membership if m['e'] not in blocked
                            and (m['e'] in rejected or (complete and m['e'] not in editions))]
            historical = {packed(m): m for m in (prior or {}).get('historicalContradictions', []) + contradicted}
            excluded = blocked | rejected
            membership = [m for m in membership if m['e'] not in excluded and (not complete or m['e'] in editions)]
            editions = sorted((set(editions) | {m["e"] for m in membership}) - blocked)
            if blocked: complete = False
            if membership: evidence = POLICY
            identity_reason = "contradictoryProductFields" if conflicting_fields else "invalidProductAssociation" if product.get("categoryId") != 2 or product.get("groupId") != gid else "invalidRarity" if rarity.lower() in INVALID_RARITIES else "ambiguousCanonicalIdentity" if len(matches) > 1 else None
            if unverified_release:
                exceptions["unverifiedRelease"].append(pid)
                identity_reason = "unverifiedRelease"
            if unsupported_code:
                exceptions['unparsedCode'].append(pid)
                identity_reason = 'unsupportedCode'
                editions, membership, complete = [], [], False
            for reason in membership_reasons: exceptions[reason].append(pid)
            # Exact source labels can corroborate a printing. Different provider
            # taxonomies require explicit, product-specific reviewed mappings;
            # equal rarity counts are never evidence of correspondence.
            source_rows = {(card_id, set_name, source_rarity) for card_id, set_name, source_rarity in entries[code]}
            exact = {row for row in source_rows if row[0] == cid
                     and norm(row[1]) == norm(group["name"]) and norm(row[2]) == norm(
                         corresponding_rarity(gid, code, physical_rarity or rarity)
                         if taxonomy_scopes is None or gid in taxonomy_scopes else (physical_rarity or rarity))}
            mapped = review.get("sourcePrintings") if review else None
            if mapped is not None:
                assert review.get("correspondenceEvidence") and mapped, f"missing correspondence evidence {pid}"
                exact = {(row["cardID"], row["setName"], row["rarity"]) for row in mapped}
                if not exact <= source_rows or any(row[0] != cid for row in exact):
                    incomplete[code].add("invalidCorrespondence")
                    exact = set()
            if not exact: incomplete[code].add("unreviewedCorrespondence")
            correspondence[pid] = exact
            rows.append({"id": stable("yugioh-printing:", "tcgplayer:2:" + str(pid)), "c": code, "g": gid, "k": card_id,
                "r": rarity, "art": " · ".join(art) or None, "p": pid, "pn": product["name"], "e": editions,
                "ec": complete, "ee": evidence, "pe": observed, "img": product.get("imageUrl"),
                "m": sorted(membership, key=lambda x: x["e"]), "ir": identity_reason,
                "limitations": membership_reasons, "correspondence": "exactOrScopedTaxonomy" if exact else "unresolvedSecondaryLink",
                "canonicalLink": "linked" if cid is not None else "unresolved",
                **({"vr": physical_rarity} if physical_rarity else {}),
                **({"on": official_name, "dn": official_name + product["name"].strip()[len(name):]} if official_name else {}),
                **({"historicalContradictions": list(historical.values())} if historical else {})})
    references, assigned_products = reference_printings(reference_inventory, reference_editions, rows, canonical, sets,
        previous_references or {}, previous or {})
    for group in sets:
        if review := scoped_release_date(reviewed_dates, group["g"], group["n"], group["a"]):
            group["d"] = review["date"]
    references += display_cards
    market_rows = [row for row in rows if row["p"] not in assigned_products]
    rows = market_rows + references
    families = collections.defaultdict(list)
    for row in rows:
        if row["c"]: families[row["c"]].append(row)
    release_name_counts = collections.Counter((row['g'], norm(row['pn'])) for row in rows)
    auto = []
    inventories = printing_inventory if isinstance(printing_inventory, list) else [printing_inventory] if printing_inventory else []
    release_inventories = {}
    for inventory in inventories:
        assert inventory['rule'] == FAMILY_RULE and inventory['language'] == 'en'
        assert inventory['count'] == len(inventory['rows']) > 0
        assert inventory['groupID'] not in release_inventories, 'duplicate release scope'
        official_names = collections.defaultdict(list)
        for entry in inventory['rows']:
            official_names[norm(entry['name'])].append(entry)
        release_inventories[inventory['groupID']] = (inventory, official_names)
    for code, family in families.items():
        source_rows = set(entries[code])
        matched = set().union(*(correspondence.get(x.get("p"), set()) for x in family))
        if matched != source_rows: incomplete[code].add("printingCorrespondenceGap")
        if not entries[code] or len({x["r"] for x in family}) < len({r for _, _, r in entries[code]}): incomplete[code].add("rarityShortfall")
        if len({(x["g"], x["r"], x["art"]) for x in family}) < len(entries[code]): incomplete[code].add("printingShortfall")
        labels = [(x["g"], x["r"], x["art"], x["pn"]) for x in family]
        if len(set(labels)) != len(labels): incomplete[code].add("indistinguishable")
        counts = collections.Counter(labels)
        for row in family:
            if counts[(row["g"], row["r"], row["art"], row["pn"])] > 1: row["ir"] = "indistinguishableProduct"
        if not incomplete[code] and len(family) == 1 and len(entries[code]) == 1 and "p" in family[0] and "pg" not in family[0] and not family[0]["art"] and not family[0]['ir'] and family[0]['e'] and family[0]['ee']:
            cid = entries[code][0][0]
            row = family[0]
            inventory, official_names = release_inventories.get(row['g'], (None, {}))
            official = official_names.get(norm(row['pn']), [])
            # Release inventory covers all names, rarities and displayed artwork.
            # Certify reviewed release scopes with an exact, unique two-source
            # crosswalk; marketplace membership still says nothing about editions
            # being exhaustive. No name aliases or artwork inference here.
            verified_family = (inventory is not None and code.startswith(inventory['codePrefix'])
                and row['r'] in inventory['rarities'] and len(official) == 1
                and official[0]['rarities'] == [row['r']] and official[0]['artwork'] == 1
                and norm(by_id[cid]['name']) == norm(row['pn'])
                and release_name_counts[(row['g'], norm(row['pn']))] == 1)
            if len(by_id[cid].get("card_images", [])) == 1 and (row['ec'] or verified_family):
                if verified_family:
                    row['pf'] = {k: inventory[k] for k in ('rule', 'url', 'sha256', 'count', 'capturedAt', 'productsSHA256', 'groupID', 'codePrefix', 'language', 'rarities')}
                auto.append(code)
    for card in canonical.values():
        if correction := (passcode_corrections or {}).get(str(card["sourceID"])):
            if card["n"] != correction["name"]:
                exceptions["canonicalPasscodeEvidenceDrift"].append(card["sourceID"])
                continue
            passcodes = correction["passcodes"]
            assert passcodes and len(set(passcodes)) == len(passcodes) and correction["evidence"]
            assert all(type(value) is int and 0 < value <= 99_999_999 for value in passcodes)
            card["pc"] = sorted(passcodes)
    ordered_cards = sorted(canonical.values(), key=lambda x: x["id"])
    indices = {x["id"]: i for i, x in enumerate(ordered_cards)}
    dates = {x["g"]: x["d"] for x in sets}
    sort_row = lambda x: (x["c"], dates[x["g"]], x["r"], x["art"] or "", x.get("p", 0))
    market_rows.sort(key=sort_row)
    references.sort(key=sort_row)
    for row in rows: row["k"] = indices[row["k"]]
    assert len(families) >= floor, "catalog below sanity floor"
    assert len({x["id"] for x in rows}) == len(rows)
    seed = {"schemaVersion": 1, "policyVersion": POLICY, "generation": "", "capturedAt": captured_at, "sets": sets, "cards": ordered_cards,
        "printings": market_rows, "incompleteCodes": sorted(k for k, v in incomplete.items() if v), "autoEligibleCodes": sorted(auto)}
    if references:
        seed["referencePrintings"] = references
    if reference_inventory:
        seed["referenceInventory"] = {"url": reference_inventory["url"], "sha256": reference_inventory["sha256"]}
    seed["generation"] = "yugioh-en-" + hashlib.sha256(packed(seed)).hexdigest()[:12]
    validate_output(seed)
    stats = {"groups": len(groups), "products": sum(map(len, products.values())), "printings": len(rows), "codes": len(families),
        "incompleteCodes": len(seed["incompleteCodes"]), "automaticCodes": len(auto),
        "verifiedPhysicalProducts": sum(x["ec"] for x in rows), "unknownCoverageProducts": sum(not x["ec"] for x in rows),
        "manualEligibleProducts": sum(bool(x["e"]) and not x["ir"] for x in rows),
        "observedLanes": dict(collections.Counter(e for x in rows for e in x["pe"]))}
    source_ids = {product["productId"] for group_products in products.values() for product in group_products}
    status = collections.Counter("discoveryOnly" if x['ir'] in ('unsupportedCode', 'unnumberedDisplay') else "quarantined" if x["ir"] else "discoveryOnly" if not x["e"] else "automaticAcquisitionEligible" if x["c"] in auto else "explicitChoiceOnlyEligible" for x in rows if x.get("p") in source_ids)
    stats["productStatusPartition"] = {k: status[k] for k in ('automaticAcquisitionEligible', 'explicitChoiceOnlyEligible', 'discoveryOnly', 'quarantined')}
    stats["legitimatelyExcluded"] = len(exceptions["foreignLanguage"])
    stats["excludedPendingClassification"] = {k: len(exceptions[k]) for k in ("noNumber", "noRarity")}
    stats["supportedPairs"] = sum(len(x["e"]) for x in rows)
    stats["quotePairs"] = sum(m["q"] is not None for x in rows for m in x["m"])
    stats["referencePrintings"] = len(references)
    stats["referencePrintingsWithEditionEvidence"] = sum(bool(row["e"]) for row in references)
    return seed, stats, exceptions, incomplete

def read_price_receipts(paths):
    groups = {}
    for path in paths:
        receipt = json.loads(path.read_text())
        marker = receipt["snapshot_start"]
        assert marker and receipt["snapshot_stable"] and marker == receipt["snapshot_end"], "unstable price receipt"
        for row in receipt["groups"]:
            group = row["group"]
            assert group not in groups, f"multiple price receipts for group {group}"
            groups[group] = (marker, row["sha256"])
    return groups


def populated_released_groups(seed, previous):
    prior_ids = {row["g"] for row in previous["printings"]}
    new_counts = collections.Counter(row["g"] for row in seed["printings"] if row["g"] not in prior_ids)
    captured_day = datetime.datetime.fromisoformat(seed["capturedAt"]).date()
    released = []
    for group in seed["sets"]:
        count = new_counts[group["g"]]
        raw_date = group["d"] or group.get("created")
        if not count or not raw_date:
            continue
        try:
            release_day = datetime.date.fromisoformat(raw_date[:10])
        except ValueError:
            continue
        if release_day <= captured_day:
            released.append({"groupID": group["g"], "code": group["a"], "providerDate": str(release_day),
                             "candidatePrintings": count})
    return released


def all_printings(seed):
    return seed["printings"] + seed.get("referencePrintings", [])


def catalog_regressions(seed, parent):
    if parent is None:
        return {}
    current = {p["id"]: p for p in all_printings(seed)}
    removed, withdrawn, changed = [], [], []
    for prior in all_printings(parent):
        printing = current.get(prior["id"])
        if printing is None:
            removed.append({"id": prior["id"], "code": prior["c"], "groupID": prior["g"]})
            continue
        immutable = ["g", "c", "r", "art", "pn"]
        if "p" in prior:
            immutable += ["p", "pg"]
        if (any(prior.get(key) != printing.get(key) for key in immutable)
                or parent["cards"][prior["k"]]["id"] != seed["cards"][printing["k"]]["id"]):
            changed.append({"id": prior["id"], "code": prior["c"], "groupID": prior["g"]})
        if not prior.get("ir"):
            lost = sorted(set(prior["e"]) - (set() if printing.get("ir") else set(printing["e"])))
            if lost:
                withdrawn.append({"id": prior["id"], "code": prior["c"], "editions": lost})
    return {key: value for key, value in {
        "removedPrintings": removed, "changedPrintingIdentities": changed, "withdrawnEditions": withdrawn,
        "withdrawnAutomaticCodes": sorted(set(parent["autoEligibleCodes"]) - set(seed["autoEligibleCodes"])),
    }.items() if value}


def release_coverage(seed, groups, calendar, profiles, reference_inventory, parent, reviewed_dates=None,
                     supplemental_checklists=None):
    """Compare verified inventories even when market data for a release is absent."""
    targets = release_checklist_targets(groups, calendar, reviewed_dates, supplemental_checklists)
    exact_codes = {release["printingCode"] for _, release in targets.values() if "printingCode" in release}
    by_name = collections.defaultdict(set)
    by_code = collections.defaultdict(set)
    counts = collections.Counter()
    for row in all_printings(seed):
        name = row.get("on") or seed["cards"][row["k"]]["n"]
        rarity = row.get("vr", row["r"])
        normalized_name = norm(name)
        by_name[(row["g"], normalized_name, None)].add(rarity)
        by_code[row["c"]].add((normalized_name, rarity))
        counts[row["g"]] += 1
        if row["c"] in exact_codes:
            by_name[(row["g"], normalized_name, row["c"])].add(rarity)
            counts[(row["g"], row["c"])] += 1
    parent_by_name = collections.defaultdict(set)
    parent_counts = collections.Counter()
    if parent:
        for row in all_printings(parent):
            name = row.get("on") or parent["cards"][row["k"]]["n"]
            rarity, normalized_name = row.get("vr", row["r"]), norm(name)
            parent_by_name[(row["g"], normalized_name, None)].add(rarity)
            parent_counts[row["g"]] += 1
            if row["c"] in exact_codes:
                parent_by_name[(row["g"], normalized_name, row["c"])].add(rarity)
                parent_counts[(row["g"], row["c"])] += 1
    else:
        parent_counts = counts
    checked_releases = []
    for profile in profiles:
        code = profile.get("printingCode")
        def missing(index):
            return [{"name": row["name"], "rarity": rarity}
                    for row in profile["rows"] for rarity in row["rarities"]
                    if rarity not in index[(profile["groupID"], norm(row["name"]), code)]]
        checked_releases.append({"groupID": profile["groupID"], "url": profile["url"], "sha256": profile.get("sha256"),
                                 "expectedCards": profile["count"], "missingNameOrRarity": missing(by_name),
                                 "parentMissingNameOrRarity": missing(parent_by_name) if parent else [],
                                 **({"printingCode": code} if code else {})})
    reference_releases = []
    for release in reference_inventory["releases"]:
        missing = [code for code, _, name, rarity in release["rows"] if (norm(name), rarity) not in by_code[code]]
        reference_releases.append({"groupID": release["groupID"], "release": release["name"],
                                   "expectedPrintings": len(release["rows"]), "missingCodeOrRarity": missing})
    captured_day = datetime.datetime.fromisoformat(seed["capturedAt"]).date()
    recent, unmatched = [], []
    for release in calendar:
        day = datetime.date.fromisoformat(release["date"])
        if not 0 <= (captured_day - day).days <= 45:
            continue
        target = targets.get(release["id"])
        if target is None:
            unmatched.append(release)
            continue
        group, target_release = target
        code = target_release.get("printingCode")
        key = (group, code) if code else group
        if not counts[key] or not parent_counts[key]:
            recent.append({**target_release, "groupID": group, "candidatePrintings": counts[key],
                           "parentPrintings": parent_counts[key]})
    undated = [{"groupID": group["g"], "release": group["n"], "printings": counts[group["g"]]}
               for group in seed["sets"] if not group["d"] and counts[group["g"]]]
    return {"checkedReleases": checked_releases, "referenceReleases": reference_releases, "recentReleaseGaps": recent,
            "unmatchedOfficialReleases": unmatched,
            "undatedPopulatedGroups": undated,
            "parentRegressions": catalog_regressions(seed, parent)}


def recent_release_checklists(groups, calendar, captured_at, cache, offline, reviewed_dates=None,
                              supplemental_checklists=None):
    """Collect current official comparison rows independently of pricing or automatic eligibility."""
    today = datetime.datetime.fromisoformat(captured_at).date()
    checklists, unavailable = [], []
    for group, release in release_checklist_targets(groups, calendar, reviewed_dates, supplemental_checklists).values():
        if not 0 <= (today - datetime.date.fromisoformat(release["date"])).days <= 45:
            continue
        release_id = release["id"]
        assert release_id.isascii() and release_id.isdigit(), "invalid official release identifier"
        url = ("https://www.db.yugioh-card.com/yugiohdb/card_search.action"
               f"?ope=1&pid={release_id}&rp=99999&request_locale=en")
        profile = {"groupID": group, "releaseName": release["name"], "url": url}
        if "printingCode" in release:
            profile["printingCode"] = release["printingCode"]
        path = cache / "konami" / f"{release_id}.html"
        try:
            if path.exists() or offline:
                raw = path.read_bytes()
                inventory = extract_inventory(raw, profile, require_unique_card_ids=False)
            else:
                request = urllib.request.Request(url, headers={"User-Agent": "CardScanner catalog builder"})
                with urllib.request.urlopen(request, timeout=15) as response:
                    raw = response.read(8 * 1024 * 1024 + 1)
                if len(raw) > 8 * 1024 * 1024:
                    raise ValueError("release inventory exceeded size limit")
                inventory = extract_inventory(raw, profile, require_unique_card_ids=False)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            checklists.append({**profile, **inventory})
        except (AssertionError, ValueError, OSError) as error:
            unavailable.append({"groupID": group, "name": release["name"], "url": url, "reason": str(error)})
    return checklists, unavailable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--previous-seed", type=pathlib.Path)
    parser.add_argument("--price-receipt", action="append", type=pathlib.Path, default=[],
                        help="Offline price receipt binding a capture to raw hashes; repeat for disjoint group scopes")
    parser.add_argument("--official-inventory-html", type=pathlib.Path, action='append', help="Captured full Konami release inventory; repeat for each reviewed release")
    parser.add_argument("--release-calendar-html", type=pathlib.Path, help="Captured English Konami release directory")
    parser.add_argument("--check-recent-official-releases", action="store_true",
                        help="Compare recent Konami release checklists with the candidate and its parent")
    parser.add_argument("--hosting-root", type=pathlib.Path, help="Stage an immutable candidate under the existing Firebase site; never deploy")
    parser.add_argument("--publication-revision", type=int, default=1, help="Candidate publication sequence, independent of provider capture time")
    args = parser.parse_args()
    if args.self_test:
        import unittest
        import sys
        sys.path.insert(0, str(ROOT))
        suite = unittest.defaultTestLoader.discover(str(ROOT / "fixtures" / "yugioh"), pattern="test_*.py")
        if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful(): raise SystemExit(1)
        return
    if not all([args.cache_dir, args.out, args.report]): parser.error("--cache-dir, --out and --report are required")
    provenance = []
    def fetch(url, relative, tcg=True):
        path = args.cache_dir / relative
        if not path.exists():
            if args.offline: raise RuntimeError(f"missing offline input: {relative}")
            for attempt in range(4):
                try:
                    time.sleep(.25)
                    data = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "CardScanner catalog builder"}), timeout=90).read()
                    value = json.loads(data)
                    if tcg and (value.get("success") is not True or value.get("errors")): raise ValueError("provider failed")
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(data)
                    break
                except Exception:
                    if attempt == 3: raise
                    time.sleep(2 ** attempt)
        data = path.read_bytes()
        value = json.loads(data)
        if tcg and (value.get("success") is not True or value.get("errors")): raise ValueError(f"invalid cached response: {relative}")
        if tcg and value.get("totalItems", len(value["results"])) != len(value["results"]): raise ValueError(f"incomplete response: {relative}")
        provenance.append({"url": url, "sha256": hashlib.sha256(data).hexdigest(), "cachedAt": datetime.datetime.fromtimestamp(path.stat().st_mtime, datetime.timezone.utc).isoformat(), "sourceUpdatedAt": value.get("lastUpdated")})
        return value["results"] if tcg else value["data"]
    base = "https://tcgcsv.com/tcgplayer"
    categories = fetch(base + "/categories", "tcgcsv/categories.json")
    assert [x["name"] for x in categories if x["categoryId"] == 2] == ["YuGiOh"]
    groups = fetch(base + "/2/groups", "tcgcsv/groups.json")
    receipt_groups = read_price_receipts(args.price_receipt)
    products, prices, price_provenance, product_hashes = {}, {}, {}, {}
    for index, group in enumerate(groups):
        gid = group["groupId"]
        products[gid] = fetch(f"{base}/2/{gid}/products", f"tcgcsv/{gid}-products.json")
        product_hashes[gid] = provenance[-1]['sha256']
        prices[gid] = fetch(f"{base}/2/{gid}/prices", f"tcgcsv/{gid}-prices.json")
        source = provenance[-1]
        if gid in receipt_groups:
            marker, expected_hash = receipt_groups[gid]
            assert source["sha256"] == expected_hash, f"snapshot hash mismatch {gid}"
        else:
            marker = source["sourceUpdatedAt"]
        price_provenance[gid] = {"h": source["sha256"], "s": marker or source["cachedAt"],
                                 "st": "providerSnapshot" if marker else "capturedAt"}
        if index % 25 == 0: print(f"Fetched {index + 1}/{len(groups)} groups", flush=True)
    cards = fetch("https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes", "ygoprodeck/cardinfo.json", False)
    timestamp = max(x["cachedAt"] for x in provenance)
    previous = json.loads(args.previous_seed.read_text()) if args.previous_seed else None
    if previous: assert previous.get("policyVersion") == POLICY, "unrecognized historical membership policy"
    taxonomy_scopes = {r['groupID'] for r in CORRESPONDENCE_RULES['rules'] if product_hashes.get(r['groupID']) == r['expectedProductsSHA256']}
    profiles = [json.loads((ROOT / name).read_text()) for name in json.loads((ROOT / 'yugioh_printing_inventories.json').read_text())['inventories']]
    inventories = reviewed_inventories(profiles, products, product_hashes, args.official_inventory_html or [])
    timestamp = max([timestamp] + [i["capturedAt"] for i in inventories])
    calendar = (extract_release_calendar(args.release_calendar_html.read_bytes()) if args.release_calendar_html
                else json.loads((ROOT / "yugioh_release_calendar.json").read_text()))
    printing_corrections = json.loads((ROOT / "yugioh_printing_corrections.json").read_text())
    reference_inventory = json.loads((ROOT / "yugioh_legacy_inventory.json").read_text())
    reference_editions = json.loads((ROOT / "yugioh_legacy_edition_evidence.json").read_text())
    physical_editions = json.loads((ROOT / "yugioh_physical_editions.json").read_text())["products"]
    release_evidence = json.loads((ROOT / "yugioh_release_date_evidence.json").read_text())
    release_dates = release_evidence["groups"]
    supplemental_checklists = release_evidence["supplementalChecklists"]
    timestamp = max(timestamp, reference_editions["capturedAt"],
                    *(source["capturedAt"] for source in reference_editions.get("galleryEvidence", {}).get("sources", [])),
                    *(review.get("reviewedAt", timestamp) for review in physical_editions.values()))
    prior_products = {p["p"]: {**p, "priorCanonical": previous["cards"][p["k"]]}
                      for p in all_printings(previous) if "p" in p} if previous else None
    seed, stats, exceptions, incomplete = build(groups, products, prices, cards, json.loads((ROOT / "yugioh_name_aliases.json").read_text()), physical_editions, timestamp,
        price_provenance=price_provenance, previous=prior_products,
        taxonomy_scopes=taxonomy_scopes, printing_inventory=inventories, release_calendar=calendar["releases"],
        rarity_corrections=printing_corrections["products"], reference_inventory=reference_inventory, reference_editions=reference_editions,
        previous_references={x["id"]: x for x in previous.get("referencePrintings", [])} if previous else None,
        reviewed_dates=release_dates, passcode_corrections=printing_corrections.get("canonicalPasscodes"))
    stats["releaseCalendar"] = {"url": calendar["url"], "sha256": calendar["sha256"],
                                "datedGroups": sum(bool(group["d"]) for group in seed["sets"])}
    stats["printingInventoryDriftGroups"] = sorted({p["groupID"] for p in profiles} - {i["groupID"] for i in inventories})
    if inventories:
        stats['printingFamilyRule'] = FAMILY_RULE
        stats['printingFamilySources'] = [{k: i[k] for k in ('url', 'sha256', 'count', 'capturedAt', 'productsSHA256', 'groupID', 'codePrefix', 'rarities')} for i in inventories]
        stats['certifiedPrintingFamilies'] = sum(bool(p.get('pf')) for p in seed['printings'])
        stats['excludedProductsInReviewedReleases'] = sum(p['g'] in {i['groupID'] for i in inventories} and not p.get('pf') for p in seed['printings'])
    stats['correspondenceRuleVersion'] = CORRESPONDENCE_RULES['version']
    stats['taxonomyScopeDriftGroups'] = sorted({r['groupID'] for r in CORRESPONDENCE_RULES['rules']} - taxonomy_scopes)
    if previous:
        stats["populatedReleasedGroupsMissingFromParent"] = populated_released_groups(seed, previous)
    unavailable = []
    checklists = []
    if args.check_recent_official_releases:
        checklists, unavailable = recent_release_checklists(groups, calendar["releases"], timestamp, args.cache_dir,
            args.offline, release_dates, supplemental_checklists)
    coverage_profiles = {(profile["groupID"], profile.get("printingCode")): profile for profile in profiles + checklists}
    coverage = release_coverage(seed, groups, calendar["releases"], coverage_profiles.values(), reference_inventory,
        previous, release_dates, supplemental_checklists)
    coverage["unavailableOfficialChecklists"] = unavailable
    stats["recentOfficialReleaseGaps"] = len(coverage["recentReleaseGaps"])
    stats["unmatchedOfficialReleases"] = len(coverage["unmatchedOfficialReleases"])
    stats["officialChecklistsWithGaps"] = sum(bool(row["missingNameOrRarity"] or row["parentMissingNameOrRarity"])
                                              for row in coverage["checkedReleases"])
    stats["unavailableOfficialChecklists"] = len(unavailable)
    stats["parentAuthorityRegressions"] = {key: len(value) for key, value in coverage["parentRegressions"].items()}
    retained = {p['p'] for p in all_printings(seed) if 'p' in p}
    excluded = []
    for gid in sorted(products):
        for p in products[gid]:
            if p['productId'] in retained: continue
            code, reason = excluded_product_reason(p, p['productId'] in exceptions['foreignLanguage'])
            excluded.append({'productID':p['productId'], 'groupID':gid, 'name':p['name'], 'code':code, 'reason':reason,
                'status':'legitimatelyExcluded' if reason != 'missingPrintedIdentity' else 'discoveryPendingIdentity'})
    stats['upstreamDisposition'] = dict(collections.Counter(x['status'] for x in excluded))
    stats['legitimatelyExcluded'] = stats['upstreamDisposition'].get('legitimatelyExcluded', 0)
    stats['excludedPendingClassification'] = {'missingPrintedIdentity':stats['upstreamDisposition'].get('discoveryPendingIdentity', 0)}
    stats['sourceProductStatusPartition'] = {
        **stats['productStatusPartition'], 'legitimatelyExcluded': stats['legitimatelyExcluded'],
        'discoveryPendingIdentity': stats['upstreamDisposition'].get('discoveryPendingIdentity', 0),
    }
    assert sum(stats['sourceProductStatusPartition'].values()) == stats['products']
    report = "# Yu-Gi-Oh catalog build report\n\nPolicy: " + POLICY + ". Raw offline source replay; cross-snapshot audit projection is not an input.\n\nCaptured through " + timestamp + ". All groups read successfully.\n\nPositive exact-product observations support explicit edition choices; they do not establish physical coverage or current prices. No group unions authorize editions. Product-status precedence is contradiction, discovery without membership, automatic eligibility, then explicit choice. Unsupported grammar remains discovery-only. The separate exclusions ledger preserves every upstream omitted product and its reason.\n\n```json\n" + json.dumps(stats, indent=2) + "\n```\n"
    for reason, examples in sorted(exceptions.items()): report += f"\n## {reason}: {len(examples)}\n\n{examples[:50]}\n"
    report += "\n## Incomplete reasons\n\n" + json.dumps(dict(collections.Counter(r for v in incomplete.values() for r in v)), sort_keys=True) + "\n"
    report += "\n## Source provenance\n\nEach input records URL, cache timestamp, provider timestamp when supplied, and SHA-256.\n\n```json\n" + json.dumps(provenance, indent=2) + "\n```\n"
    # No output changes until every input and invariant passed.
    validate_output(seed, strict=True)
    for path, data in [(args.out, packed(seed)), (args.report, report.encode()),
                       (args.report.with_suffix('.exclusions.json'), packed(excluded)),
                       (args.report.with_suffix('.coverage.json'), packed(coverage))]:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(data)
        temporary.replace(path)
    if args.hosting_root:
        if coverage["parentRegressions"]:
            print("::warning title=Yu-Gi-Oh! candidate requires review::See coverage report for lost printing or edition authority.")
        else:
            stage_hosting(seed, args.hosting_root, args.publication_revision)
    if os.environ.get("GITHUB_ACTIONS") == "true" and (
            stats["recentOfficialReleaseGaps"] or stats["unmatchedOfficialReleases"]
            or stats["officialChecklistsWithGaps"] or unavailable):
        print("::warning title=Yu-Gi-Oh! official coverage needs review::See the coverage report for missing rows or sources.")
    if stats.get("populatedReleasedGroupsMissingFromParent"):
        ids = ", ".join(str(row["groupID"]) for row in stats["populatedReleasedGroupsMissingFromParent"])
        message = f"Provider-dated Yu-Gi-Oh! groups with candidate printings absent from the parent: {ids}"
        if os.environ.get("GITHUB_ACTIONS") == "true":
            message = "::warning title=Yu-Gi-Oh! catalog publication lag::" + message
        print(message)
    print(json.dumps(stats, indent=2))

def validate_output(seed, strict=False):
    """Check admission invariants before writing any candidate artifacts."""
    families = collections.defaultdict(list)
    assert seed['schemaVersion'] == 1 and seed['policyVersion'] == POLICY
    captured = datetime.datetime.fromisoformat(seed['capturedAt'].replace('Z', '+00:00'))
    ids, products = set(), set()
    for index, row in enumerate(all_printings(seed)):
        assert row['id'] not in ids, 'duplicate identity'
        ids.add(row['id'])
        if 'p' in row:
            assert row['p'] not in products and row['p'] > 0, 'duplicate identity'
            products.add(row['p'])
        else:
            assert index >= len(seed['printings']) and not row['pe'] and not row['ec'] and 'pg' not in row
            assert all(m['t'] == 'independentlyReviewed' and m['q'] is None for m in row['m'])
        assert str(uuid.UUID(row['id'])) == row['id'] and 0 <= row['k'] < len(seed['cards'])
        unnumbered_display = (index >= len(seed['printings']) and row['c'] == '' and row['ir'] == 'unnumberedDisplay'
                             and 'p' in row and not row['e'] and not row['pe'] and not row['ec'] and not row['m'])
        assert (CODE.fullmatch(row['c']) or unnumbered_display
                or (row['ir'] == 'unsupportedCode' and row['c'] and not row['e']))
        families[row['c']].append(row)
        assert len(row['e']) == len(set(row['e'])) and set(row['e']) <= set(LANES.values())
        assert len(row['m']) == len({m['e'] for m in row['m']})
        assert set(m['e'] for m in row['m']) <= set(row['e']), 'membership outside admitted editions'
        assert row['ec'] or set(row['e']) == set(m['e'] for m in row['m']), 'unsupported edition'
        for m in row['m']:
            assert m['t'] in ('providerMarket', 'providerListing', 'independentlyReviewed')
            assert m['q'] is None or (type(m['q']) in (int, float) and math.isfinite(m['q']) and m['q'] >= 0)
            if strict:
                assert re.fullmatch('[a-f0-9]{64}', m.get('h', '')), 'missing source hash'
                assert datetime.datetime.fromisoformat(m.get('s', '').replace('Z', '+00:00')) <= captured, 'future membership evidence'
    assert set(seed['autoEligibleCodes']).isdisjoint(seed['incompleteCodes'])
    for code in seed['autoEligibleCodes']:
        family = families[code]
        assert len(family) == 1, 'automatic family is not a singleton'
        row = family[0]
        assert not row['ir'] and (row['ec'] or row.get('pf')) and row['e'] and row['ee'], 'automatic row lacks admission evidence'
        if row.get('pf'):
            assert row['pf']['rule'] == FAMILY_RULE and row['g'] == row['pf']['groupID'] and row['c'].startswith(row['pf']['codePrefix']) and row['r'] in row['pf']['rarities']
            assert row['pf']['count'] > 0 and row['pf']['language'] == 'en' and not row['art']
            assert all(re.fullmatch('[a-f0-9]{64}', row['pf'][k]) for k in ('sha256', 'productsSHA256'))

def stage_hosting(seed, root, revision=1):
    """An isolated namespace on the existing host. No deploy/signing authority."""
    validate_output(seed, strict=True)
    if type(revision) is not int or not 1 <= revision <= 100000: raise ValueError('publication revision must be in 1...100000')
    data = packed(seed)
    relative = pathlib.Path('yugioh/v1/releases') / seed['generation'] / 'catalog.json'
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() != data: raise ValueError('immutable candidate collision')
    target.write_bytes(data)
    manifest = {'schemaVersion':1, 'revision':revision, 'generation':seed['generation'], 'policyVersion':POLICY,
                'path':str(relative), 'sha256':hashlib.sha256(data).hexdigest(), 'bytes':len(data),
                'status':'candidate_not_deployed', 'capturedAt':seed['capturedAt']}
    # Unsigned staging is never the production approval pointer.
    pointer = root / 'yugioh/v1/candidate.json'
    pointer.write_bytes(packed(manifest))

if __name__ == "__main__": main()
