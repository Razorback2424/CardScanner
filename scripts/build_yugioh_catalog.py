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
import pathlib
import re
import time
import unicodedata
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parent
LANES = {"1st Edition": "yugioh1stEdition", "Unlimited": "yugiohUnlimited", "Limited": "yugiohLimited"}
RARITIES = set("UR SR SCR SE UTR ULR PUR PCR PSR QCSR QCR GR STR CR R C SP SSP MSR ESR GSR PGR".split())
CODE = re.compile(r"^(?:[A-Z0-9]{2,4}-(?:(?:EN|E)[A-Z0-9]{3}|[0-9]{3})|IOC-SE[1-4])$")
POLICY = "yugioh-provider-membership-v1-2026-10-21"
INVALID_RARITIES = {"new", "2", "3", "new artwork"}
PRICE_FIELDS = ("marketPrice", "lowPrice", "midPrice", "highPrice", "directLowPrice")
CORRESPONDENCE_RULES = json.loads((ROOT / 'yugioh_correspondence_rules.json').read_text())

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

def norm(value):
    return " ".join(re.sub(r"[^a-z0-9]+", " ", unicodedata.normalize("NFKD", value).lower()).split())

def stable(namespace, material):
    return str(uuid.UUID(bytes=hashlib.md5((namespace + material).encode()).digest(), version=3))

def packed(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()

def build(groups, products, prices, cards, aliases, reviews, captured_at, floor=10000, price_provenance=None, previous=None, taxonomy_scopes=None):
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
    for group in sorted(groups, key=lambda x: x["groupId"]):
        gid = group["groupId"]
        sets.append({"g": gid, "n": group["name"], "a": group.get("abbreviation") or "", "d": "",
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
            key = "ygoprodeck:" + str(cid) if cid is not None else "name:" + norm(name)
            card_id = stable("yugioh-card:", key)
            source = by_id.get(cid, {})
            canonical[card_id] = {"id": card_id, "n": source.get("name", name),
                "pc": [cid] if cid is not None and 0 < cid <= 99999999 else [],
                "sourceID": cid, "imageIDs": [i["id"] for i in source.get("card_images", [])]}
            if cid is None: incomplete[code].add("nameMismatch")
            elif norm(name) != norm(source["name"]): exceptions["aliasMatch"].append(pid)
            review = reviews.get(str(pid))
            editions, complete, evidence = [], False, None
            if review:
                assert review.get("evidence") and set(review["editions"]) <= set(LANES.values()) and review["editions"]
                editions = sorted(set(review["editions"]))
                complete, evidence = review.get("complete") is True, review["evidence"]
                if complete:
                    assert {m['e'] for m in grade_prices(product_prices[pid])[0]} <= set(editions), f"review/price contradiction {pid}"
            if not complete: exceptions["physicalCoverageUnknown"].append(pid)
            membership, membership_reasons = grade_prices(product_prices[pid])
            blocked = {r.split(':', 1)[1] for r in membership_reasons if r.startswith(('conflictingDuplicate:', 'invalidNumeric:'))}
            provenance = (price_provenance or {}).get(gid, {})
            for m in membership: m.update(provenance)
            if review:
                for edition in editions:
                    if edition not in {m['e'] for m in membership}:
                        membership.append({'e':edition, 't':'independentlyReviewed', 'q':None,
                            'h':hashlib.sha256(packed(review)).hexdigest(), 's':captured_at, 'st':'reviewedAt'})
            # Historical support survives absence, but explicit conflicting rows
            # retract only their affected lane. No edition transfer across products.
            prior = (previous or {}).get(pid)
            if prior and (prior["g"], prior["c"], prior["r"], prior["pn"]) == (gid, code, rarity, product["name"]):
                for m in prior.get("m", []):
                    if m["e"] not in {x["e"] for x in membership} | blocked and m.get("h") and m.get("s"):
                        membership.append({**m, "q": None})
            membership = [m for m in membership if m['e'] not in blocked]
            if complete:
                contradicted = [m for m in membership if m['e'] not in editions]
                membership = [m for m in membership if m['e'] in editions]
            else:
                contradicted = []
            editions = sorted((set(editions) | {m["e"] for m in membership}) - blocked)
            if blocked: complete = False
            if membership: evidence = POLICY
            identity_reason = "contradictoryProductFields" if conflicting_fields else "invalidProductAssociation" if product.get("categoryId") != 2 or product.get("groupId") != gid else "invalidRarity" if rarity.lower() in INVALID_RARITIES else "ambiguousCanonicalIdentity" if len(matches) > 1 else None
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
                     and norm(row[1]) == norm(group["name"]) and norm(row[2]) == norm(corresponding_rarity(gid, code, rarity) if taxonomy_scopes is None or gid in taxonomy_scopes else rarity)}
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
                **({"historicalContradictions": (prior or {}).get('historicalContradictions', []) + contradicted}
                   if contradicted or (prior or {}).get('historicalContradictions') else {})})
    families = collections.defaultdict(list)
    for row in rows: families[row["c"]].append(row)
    auto = []
    for code, family in families.items():
        source_rows = set(entries[code])
        matched = set().union(*(correspondence[x["p"]] for x in family))
        if matched != source_rows: incomplete[code].add("printingCorrespondenceGap")
        if not entries[code] or len({x["r"] for x in family}) < len({r for _, _, r in entries[code]}): incomplete[code].add("rarityShortfall")
        if len({(x["g"], x["r"], x["art"]) for x in family}) < len(entries[code]): incomplete[code].add("printingShortfall")
        labels = [(x["g"], x["r"], x["art"], x["pn"]) for x in family]
        if len(set(labels)) != len(labels): incomplete[code].add("indistinguishable")
        counts = collections.Counter(labels)
        for row in family:
            if counts[(row["g"], row["r"], row["art"], row["pn"])] > 1: row["ir"] = "indistinguishableProduct"
        if not incomplete[code] and len(family) == 1 and len(entries[code]) == 1 and not family[0]["art"] and family[0]["ec"] and not family[0]['ir'] and family[0]['e'] and family[0]['ee']:
            cid = entries[code][0][0]
            if len(by_id[cid].get("card_images", [])) == 1: auto.append(code)
    ordered_cards = sorted(canonical.values(), key=lambda x: x["id"])
    indices = {x["id"]: i for i, x in enumerate(ordered_cards)}
    dates = {x["g"]: x["d"] for x in sets}
    rows.sort(key=lambda x: (x["c"], dates[x["g"]], x["r"], x["art"] or "", x["p"]))
    for row in rows: row["k"] = indices[row["k"]]
    assert len(families) >= floor, "catalog below sanity floor"
    assert len({x["id"] for x in rows}) == len(rows)
    assert len({(x["g"], x["p"]) for x in rows}) == len(rows)
    seed = {"schemaVersion": 1, "policyVersion": POLICY, "generation": "", "capturedAt": captured_at, "sets": sets, "cards": ordered_cards,
        "printings": rows, "incompleteCodes": sorted(k for k, v in incomplete.items() if v), "autoEligibleCodes": sorted(auto)}
    seed["generation"] = "yugioh-en-" + hashlib.sha256(packed(seed)).hexdigest()[:12]
    validate_output(seed)
    stats = {"groups": len(groups), "products": sum(map(len, products.values())), "printings": len(rows), "codes": len(families),
        "incompleteCodes": len(seed["incompleteCodes"]), "automaticCodes": len(auto),
        "verifiedPhysicalProducts": sum(x["ec"] for x in rows), "unknownCoverageProducts": sum(not x["ec"] for x in rows),
        "manualEligibleProducts": sum(bool(x["e"]) and not x["ir"] for x in rows),
        "observedLanes": dict(collections.Counter(e for x in rows for e in x["pe"]))}
    status = collections.Counter("discoveryOnly" if x['ir'] == 'unsupportedCode' else "quarantined" if x["ir"] else "discoveryOnly" if not x["e"] else "automaticAcquisitionEligible" if x["c"] in auto else "explicitChoiceOnlyEligible" for x in rows)
    stats["productStatusPartition"] = {k: status[k] for k in ('automaticAcquisitionEligible', 'explicitChoiceOnlyEligible', 'discoveryOnly', 'quarantined')}
    stats["legitimatelyExcluded"] = len(exceptions["foreignLanguage"])
    stats["excludedPendingClassification"] = {k: len(exceptions[k]) for k in ("noNumber", "noRarity")}
    stats["supportedPairs"] = sum(len(x["e"]) for x in rows)
    stats["quotePairs"] = sum(m["q"] is not None for x in rows for m in x["m"])
    return seed, stats, exceptions, incomplete

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--previous-seed", type=pathlib.Path)
    parser.add_argument("--price-receipt", type=pathlib.Path, help="Offline census receipt; binds provider snapshot time to exact raw hashes")
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
    receipt = json.loads(args.price_receipt.read_text()) if args.price_receipt else None
    if receipt:
        assert receipt['snapshot_stable'] and receipt['snapshot_start'] == receipt['snapshot_end']
    receipt_groups = {x['group']: x for x in receipt['groups']} if receipt else {}
    products, prices, price_provenance, product_hashes = {}, {}, {}, {}
    for index, group in enumerate(groups):
        gid = group["groupId"]
        products[gid] = fetch(f"{base}/2/{gid}/products", f"tcgcsv/{gid}-products.json")
        product_hashes[gid] = provenance[-1]['sha256']
        prices[gid] = fetch(f"{base}/2/{gid}/prices", f"tcgcsv/{gid}-prices.json")
        if gid in receipt_groups:
            assert provenance[-1]['sha256'] == receipt_groups[gid]['sha256'], f"snapshot hash mismatch {gid}"
        price_provenance[gid] = {"h": provenance[-1]["sha256"], "s": receipt['snapshot_start'] if gid in receipt_groups else provenance[-1]['sourceUpdatedAt'] or provenance[-1]['cachedAt'],
                                 "st": "providerSnapshot" if gid in receipt_groups or provenance[-1]['sourceUpdatedAt'] else "capturedAt"}
        if index % 25 == 0: print(f"Fetched {index + 1}/{len(groups)} groups", flush=True)
    cards = fetch("https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes", "ygoprodeck/cardinfo.json", False)
    timestamp = max(x["cachedAt"] for x in provenance)
    previous = json.loads(args.previous_seed.read_text()) if args.previous_seed else None
    if previous: assert previous.get("policyVersion") == POLICY, "unrecognized historical membership policy"
    taxonomy_scopes = {r['groupID'] for r in CORRESPONDENCE_RULES['rules'] if product_hashes.get(r['groupID']) == r['expectedProductsSHA256']}
    seed, stats, exceptions, incomplete = build(groups, products, prices, cards, json.loads((ROOT / "yugioh_name_aliases.json").read_text()), json.loads((ROOT / "yugioh_physical_editions.json").read_text())["products"], timestamp,
        price_provenance=price_provenance, previous={x["p"]: x for x in previous["printings"]} if previous else None, taxonomy_scopes=taxonomy_scopes)
    stats['correspondenceRuleVersion'] = CORRESPONDENCE_RULES['version']
    stats['taxonomyScopeDriftGroups'] = sorted({r['groupID'] for r in CORRESPONDENCE_RULES['rules']} - taxonomy_scopes)
    retained = {p['p'] for p in seed['printings']}
    excluded = []
    for gid in sorted(products):
        for p in products[gid]:
            if p['productId'] in retained: continue
            ext = {x['name']: x['value'] for x in p.get('extendedData', [])}
            code = ext.get('Number', '').strip().upper()
            # Bounded product-name evidence. Ambiguous missing-code singles are
            # kept in this ledger for review, never called foreign or sealed.
            sealed = not code and re.search(r'\b(?:booster (?:box|pack)|blister pack|starter deck|structure deck|playmat|sleeves|binder|sealed|collector.?s? tin)\b', p['name'], re.I)
            reason = 'foreignLanguage' if p['productId'] in exceptions['foreignLanguage'] else 'sealedOrAccessoryName' if sealed else 'missingPrintedIdentity'
            excluded.append({'productID':p['productId'], 'groupID':gid, 'name':p['name'], 'code':code, 'reason':reason,
                'status':'legitimatelyExcluded' if reason != 'missingPrintedIdentity' else 'discoveryPendingIdentity'})
    stats['upstreamDisposition'] = dict(collections.Counter(x['status'] for x in excluded))
    stats['legitimatelyExcluded'] = stats['upstreamDisposition'].get('legitimatelyExcluded', 0)
    stats['excludedPendingClassification'] = {'missingPrintedIdentity':stats['upstreamDisposition'].get('discoveryPendingIdentity', 0)}
    stats['sourceProductStatusPartition'] = {**stats['productStatusPartition'], 'legitimatelyExcluded':stats['legitimatelyExcluded']}
    stats['sourceProductStatusPartition']['discoveryOnly'] += stats['upstreamDisposition'].get('discoveryPendingIdentity', 0)
    assert sum(stats['sourceProductStatusPartition'].values()) == stats['products']
    report = "# Yu-Gi-Oh catalog build report\n\nPolicy: " + POLICY + ". Raw offline source replay; cross-snapshot audit projection is not an input.\n\nCaptured through " + timestamp + ". All groups read successfully.\n\nPositive exact-product observations support explicit edition choices; they do not establish physical coverage or current prices. No group unions authorize editions. Product-status precedence is contradiction, discovery without membership, automatic eligibility, then explicit choice. Unsupported grammar remains discovery-only. The separate exclusions ledger preserves every upstream omitted product and its reason.\n\n```json\n" + json.dumps(stats, indent=2) + "\n```\n"
    for reason, examples in sorted(exceptions.items()): report += f"\n## {reason}: {len(examples)}\n\n{examples[:50]}\n"
    report += "\n## Incomplete reasons\n\n" + json.dumps(dict(collections.Counter(r for v in incomplete.values() for r in v)), sort_keys=True) + "\n"
    report += "\n## Source provenance\n\nEach input records URL, cache timestamp, provider timestamp when supplied, and SHA-256.\n\n```json\n" + json.dumps(provenance, indent=2) + "\n```\n"
    # No output changes until every input and invariant passed.
    validate_output(seed, strict=True)
    for path, data in [(args.out, packed(seed)), (args.report, report.encode()),
                       (args.report.with_suffix('.exclusions.json'), packed(excluded))]:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(data)
        temporary.replace(path)
    if args.hosting_root:
        stage_hosting(seed, args.hosting_root, args.publication_revision)
    print(json.dumps(stats, indent=2))

def validate_output(seed, strict=False):
    """Check admission invariants before writing any candidate artifacts."""
    families = collections.defaultdict(list)
    assert seed['schemaVersion'] == 1 and seed['policyVersion'] == POLICY
    captured = datetime.datetime.fromisoformat(seed['capturedAt'].replace('Z', '+00:00'))
    ids, products = set(), set()
    for row in seed['printings']:
        assert row['id'] not in ids and row['p'] not in products and row['p'] > 0, 'duplicate identity'
        ids.add(row['id']); products.add(row['p'])
        assert str(uuid.UUID(row['id'])) == row['id'] and 0 <= row['k'] < len(seed['cards'])
        assert CODE.fullmatch(row['c']) or (row['ir'] == 'unsupportedCode' and row['c'] and not row['e'])
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
        assert not row['ir'] and row['ec'] and row['e'] and row['ee'], 'automatic row lacks admission evidence'

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
