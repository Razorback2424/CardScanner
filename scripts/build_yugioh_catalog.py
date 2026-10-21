#!/usr/bin/env python3
"""Build a deterministic English catalog. Price observations never prove edition coverage.

Reviewed physical metadata is keyed by product, with editions, complete and evidence.
An empty review file is intentional: unreviewed products remain quarantined.
"""
import argparse
import collections
import datetime
import hashlib
import json
import pathlib
import re
import time
import unicodedata
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parent
LANES = {"1st Edition": "yugioh1stEdition", "Unlimited": "yugiohUnlimited", "Limited": "yugiohLimited"}
RARITIES = set("UR SR SCR SE UTR ULR PUR PCR PSR QCSR QCR GR STR CR R C SP SSP MSR ESR GSR PGR".split())
CODE = re.compile(r"^[A-Z0-9]{2,4}-(?:(?:EN|E)[A-Z0-9]{3}|[0-9]{3})$")

def norm(value):
    return " ".join(re.sub(r"[^a-z0-9]+", " ", unicodedata.normalize("NFKD", value).lower()).split())

def stable(namespace, material):
    return str(uuid.UUID(bytes=hashlib.md5((namespace + material).encode()).digest(), version=3))

def packed(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()

def build(groups, products, prices, cards, aliases, reviews, captured_at, floor=10000):
    entries = collections.defaultdict(list)
    names, by_id = {}, {}
    for card in cards:
        cid = card["id"]
        by_id[cid] = card
        names[cid] = {norm(card["name"])} | {norm(x["beta_name"]) for x in card.get("misc_info", []) if x.get("beta_name")} | {norm(x) for x in aliases.get(str(cid), [])}
        for row in card.get("card_sets", []):
            entries[row["set_code"]].append((cid, row["set_name"], row["set_rarity"]))
    exceptions = collections.defaultdict(list)
    incomplete = collections.defaultdict(set)
    canonical, rows, sets = {}, [], []
    for group in sorted(groups, key=lambda x: x["groupId"]):
        gid = group["groupId"]
        sets.append({"g": gid, "n": group["name"], "a": group.get("abbreviation") or "", "d": (group.get("publishedOn") or "")[:10]})
        lanes = collections.defaultdict(set)
        for row in prices[gid]:
            lanes[row["productId"]].add(row["subTypeName"])
        for product in sorted(products[gid], key=lambda x: x["productId"]):
            pid = product["productId"]
            ext = {x["name"]: x["value"] for x in product.get("extendedData", [])}
            code, rarity = ext.get("Number", "").strip().upper(), ext.get("Rarity", "").strip()
            reason = "noNumber" if not code else "nonEnglishOrUnparsed" if not CODE.fullmatch(code) else "noRarity" if not rarity else None
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
            matches = {cid for cid, _, _ in entries[code] if norm(name) in names[cid]}
            cid = next(iter(matches)) if len(matches) == 1 else None
            key = "ygoprodeck:" + str(cid) if cid is not None else "name:" + norm(name)
            card_id = stable("yugioh-card:", key)
            source = by_id.get(cid, {})
            canonical[card_id] = {"id": card_id, "n": source.get("name", name), "pc": sorted({source["id"]} | {i["id"] for i in source.get("card_images", [])}) if cid is not None else []}
            if cid is None: incomplete[code].add("nameMismatch")
            elif norm(name) != norm(source["name"]): exceptions["aliasMatch"].append(pid)
            review = reviews.get(str(pid))
            editions, complete, evidence = [], False, None
            if review:
                assert review.get("evidence") and set(review["editions"]) <= set(LANES.values()) and review["editions"]
                editions = sorted(set(review["editions"]))
                complete, evidence = review.get("complete") is True, review["evidence"]
                assert set(observed) <= set(editions), f"review/price contradiction {pid}"
            if not complete: exceptions["physicalCoverageUnknown"].append(pid)
            rows.append({"id": stable("yugioh-printing:", "tcgplayer:2:" + str(pid)), "c": code, "g": gid, "k": card_id,
                "r": rarity, "art": " · ".join(art) or None, "p": pid, "pn": product["name"], "e": editions,
                "ec": complete, "ee": evidence, "pe": observed, "img": product.get("imageUrl")})
    families = collections.defaultdict(list)
    for row in rows: families[row["c"]].append(row)
    auto = []
    for code, family in families.items():
        if not entries[code] or len({x["r"] for x in family}) < len({r for _, _, r in entries[code]}): incomplete[code].add("rarityShortfall")
        if len({(x["g"], x["r"], x["art"]) for x in family}) < len(entries[code]): incomplete[code].add("printingShortfall")
        labels = [(x["g"], x["r"], x["art"]) for x in family]
        if len(set(labels)) != len(labels): incomplete[code].add("indistinguishable")
        if not incomplete[code] and len(family) == 1 and len(entries[code]) == 1 and not family[0]["art"] and family[0]["ec"]:
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
    seed = {"schemaVersion": 1, "generation": "", "capturedAt": captured_at, "sets": sets, "cards": ordered_cards,
        "printings": rows, "incompleteCodes": sorted(k for k, v in incomplete.items() if v), "autoEligibleCodes": sorted(auto)}
    seed["generation"] = "yugioh-en-" + hashlib.sha256(packed(seed)).hexdigest()[:12]
    stats = {"groups": len(groups), "products": sum(map(len, products.values())), "printings": len(rows), "codes": len(families),
        "incompleteCodes": len(seed["incompleteCodes"]), "automaticCodes": len(auto),
        "verifiedPhysicalProducts": sum(x["ec"] for x in rows), "quarantinedPhysicalProducts": sum(not x["ec"] for x in rows),
        "manualEligibleProducts": sum(x["ec"] and x["c"] not in seed["incompleteCodes"] for x in rows),
        "observedLanes": dict(collections.Counter(e for x in rows for e in x["pe"]))}
    return seed, stats, exceptions, incomplete

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--self-test", action="store_true")
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
    products, prices = {}, {}
    for index, group in enumerate(groups):
        gid = group["groupId"]
        products[gid] = fetch(f"{base}/2/{gid}/products", f"tcgcsv/{gid}-products.json")
        prices[gid] = fetch(f"{base}/2/{gid}/prices", f"tcgcsv/{gid}-prices.json")
        if index % 25 == 0: print(f"Fetched {index + 1}/{len(groups)} groups", flush=True)
    cards = fetch("https://db.ygoprodeck.com/api/v7/cardinfo.php?misc=yes", "ygoprodeck/cardinfo.json", False)
    timestamp = max(x["cachedAt"] for x in provenance)
    seed, stats, exceptions, incomplete = build(groups, products, prices, cards, json.loads((ROOT / "yugioh_name_aliases.json").read_text()), json.loads((ROOT / "yugioh_physical_editions.json").read_text())["products"], timestamp)
    report = "# Yu-Gi-Oh catalog build report\n\nCaptured through " + timestamp + ". All groups fetched successfully.\n\nPrice lanes are observations, not physical coverage or current price availability. No group unions authorize editions.\n\n```json\n" + json.dumps(stats, indent=2) + "\n```\n"
    for reason, examples in sorted(exceptions.items()): report += f"\n## {reason}: {len(examples)}\n\n{examples[:50]}\n"
    report += "\n## Incomplete reasons\n\n" + json.dumps(dict(collections.Counter(r for v in incomplete.values() for r in v)), sort_keys=True) + "\n"
    report += "\n## Source provenance\n\nEach input records URL, cache timestamp, provider timestamp when supplied, and SHA-256.\n\n```json\n" + json.dumps(provenance, indent=2) + "\n```\n"
    # No output changes until every input and invariant passed.
    for path, data in [(args.out, packed(seed)), (args.report, report.encode())]:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(data)
        temporary.replace(path)
    print(json.dumps(stats, indent=2))

if __name__ == "__main__": main()
