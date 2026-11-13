#!/usr/bin/env python3
"""Compare retained TCGCSV products with the app catalog and hosted Pokémon price feed."""
from __future__ import annotations

import argparse
import base64
from collections import Counter, defaultdict
import csv
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unicodedata
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlsplit

from capture_pokemon_tcgcsv import BASE, CATEGORY, DELAY, USER_AGENT, capture, groups_in, is_priority
from market_price_feeds import (FEED_PATH, MAX_FILE_BYTES, NAMESPACE, ORIGIN, instant, packed, read_http,
                                scope_from_repo, stamp, validate_site)
from one_piece_tcgcsv_capture import TCGCSVSnapshot

# An exact TCGCSV group to app set cross-reference for named promo releases.
# Deck Exclusives and Prize Packs span many printed sets.
PROMO_SETS = {
    1401: "2011bw", 1427: "2012bw", 1692: "2014xy", 1694: "2015xy", 3087: "2016xy",
    2148: "2017sm", 2364: "2018sm", 2555: "2019sm", 2782: "2021swsh", 3150: "2022swsh",
    23306: "2023sv", 24163: "2024sv", 24938: "tcgplayer:24938",
    1418: "basep", 1423: "np", 1421: "dpp", 1453: "hgssp", 1407: "bwp", 1451: "xyp", 1861: "smp",
    2545: "swshp", 22872: "svp", 24451: "mep",
}
STANDARD_LANES = {"normal": "Normal", "holo": "Holofoil", "reverse": "Reverse Holofoil"}
CARD_NUMBER = r"[A-Za-z]*\s*[0-9]+[A-Za-z]*"
TITLE_NUMBER = re.compile(rf"\s+-\s*({CARD_NUMBER}(?:\s*/\s*{CARD_NUMBER})?)(?=\s*(?:\(|\[|$))")
REVIEW_TREATMENT = re.compile(r"30th celebration|pok[eé]mon center|cosmos|\bstamp\b|\bstaff\b|prerelease", re.I)
APP_INPUTS = ("Config", "TradingCardScanner", "TradingCardScannerTests", "TradingCardScanner.xcodeproj",
              "PokemonCatalogCore", "MagicCatalogCore", "OnePieceCatalogCore",
              "publisher/pokemon-battle-deck-finishes.json", "publisher/pokemon-deck-exclusive-normals.json",
              "publisher/pokemon-delta-reign-printings.json", "publisher/pokemon-mcdonalds-2026.json")
AUDIT_TEST = "TradingCardScannerTests/PokemonCatalogCoordinatorTests/testExportPokemonTCGCSVAuditInventoryWhenRequested"


def stage_hosted(output: Path, fetch=read_http):
    output.mkdir(parents=True, exist_ok=True)
    envelope = fetch(ORIGIN + "/v1/current.json", 8 * 1024 * 1024)
    payload = json.loads(envelope)["payload"]
    release = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    revision = release["revision"]
    if type(revision) is not int or revision <= 0:
        raise ValueError("Invalid production Pokémon catalog revision")
    snapshot = fetch(f"{ORIGIN}/v1/releases/{revision}/pokemon-catalog-snapshot.json", 64 * 1024 * 1024)

    # The app verifies the signature and checklist digest before exporting any rows.
    (output / "current.json").write_bytes(envelope)
    (output / "pokemon-catalog-snapshot.json").write_bytes(snapshot)
    base = f"{ORIGIN}/{NAMESPACE}"
    for attempt in range(2):
        raw_index = fetch(f"{base}/index.json", 1024 * 1024)
        try:
            index = json.loads(raw_index)
            entries = [entry for entry in index["files"] if entry["path"] == "last-updated.txt"
                       or entry["path"].startswith("tcgplayer/3/")]
            files = {}
            for entry in entries:
                path, size = entry["path"], entry["byteCount"]
                if (path != "last-updated.txt" and not FEED_PATH.fullmatch(path)
                        or type(size) is not int or not 0 < size <= MAX_FILE_BYTES or path in files):
                    raise ValueError("Invalid hosted Pokémon price feed path or size")
                files[path] = fetch(f"{base}/{path}", size)
            validate_site(dict(index, files=entries), files)
            break
        except (ValueError, HTTPError):
            if attempt or fetch(f"{base}/index.json", 1024 * 1024) == raw_index:
                raise

    # Retain only the Pokémon slice of the published price index and files.
    hosted = output / "hosted-prices"
    for path, data in files.items():
        destination = hosted / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    (hosted / "index.json").write_bytes(packed(dict(index, files=entries)))
    print(f"Staged signed catalog revision {revision} and hosted Pokémon prices {index['sourceBuild']}", flush=True)


def completed_captures(root):
    captures = []
    for manifest in root.glob("*/captures.json"):
        metadata = json.loads(manifest.read_bytes())
        if metadata.get("complete") is True:
            captures.append((instant(metadata["upstreamBuild"]), manifest.parent))
    return [directory for _, directory in sorted(captures)]


def read_source(directory):
    snapshot = TCGCSVSnapshot(directory, USER_AGENT, DELAY, offline=True, category_id=CATEGORY)
    if snapshot.manifest["complete"] is not True:
        raise ValueError("Expected a completed Pokémon TCGCSV capture")
    groups = groups_in(snapshot)
    products = {}
    incomplete = []
    for group in groups:
        gid = group["groupId"]
        document = snapshot.fetch_json(f"{BASE}/{gid}/products")
        if document.get("sourceInventoryComplete") is False:
            incomplete.append(gid)
        by_product = defaultdict(dict)
        for price in snapshot.fetch_json(f"{BASE}/{gid}/prices")["results"]:
            pid, lane = price["productId"], price["subTypeName"]
            if type(pid) is not int or not isinstance(lane, str) or not lane or lane in by_product[pid]:
                raise ValueError(f"Invalid or duplicate price lane in group {gid}")
            by_product[pid][lane] = price.get("marketPrice")
        for product in document["results"]:
            pid = product["productId"]
            if (type(pid) is not int or pid <= 0 or pid in products or product["groupId"] != gid
                    or product["categoryId"] != CATEGORY):
                raise ValueError(f"Invalid or duplicate product in group {gid}")
            fields = {field["name"]: field["value"] for field in product.get("extendedData", [])}
            name = product["name"]
            number = fields.get("Number") or None
            number_source = "marketField" if number else None
            # New promo listings can publish a title before extended data or prices.
            if number is None and is_priority(group) and (match := TITLE_NUMBER.search(name)):
                number, number_source = match[1], "marketTitle"
            single = bool(number or fields.get("Card Type") or fields.get("CardType") or fields.get("HP")
                          or fields.get("Rarity")) and not name.casefold().startswith("code card")
            products[pid] = {"productID": pid, "groupID": gid, "name": name, "number": number,
                             "numberSource": number_source, "singleCardCandidate": single,
                             "lanes": by_product.pop(pid, {})}
        if by_product:
            raise ValueError(f"Price rows reference unknown products in group {gid}")
    snapshot.finish()
    return snapshot.upstream_build, groups, products, incomplete


def normalized(text):
    decomposed = unicodedata.normalize("NFKD", text.casefold().replace("♀", " female ").replace("♂", " male "))
    return "".join(character for character in decomposed if character.isalnum())


def number_parts(number):
    if not number or re.fullmatch(rf"\s*{CARD_NUMBER}(?:\s*/\s*{CARD_NUMBER})?\s*", number) is None:
        return None, None
    return tuple(re.sub(r"[0-9]+", lambda digits: str(int(digits[0])), "".join(part.upper().split()))
                 for part in (number + ("/" if "/" not in number else "")).split("/"))


def candidate_names(name):
    # Only suggestions use the shortened title. Exact product matches are keyed by ID.
    without_tags = re.sub(r"\s*(?:\([^()]+\)|\[[^\[\]]+\])", "", name)
    without_number = re.sub(rf"\s+-\s*{CARD_NUMBER}(?:\s*/\s*{CARD_NUMBER})?\s*$", "", without_tags)
    return {normalized(name), normalized(without_number)}


def indexes(inventory):
    sets, exact, by_name_and_number = defaultdict(list), defaultdict(list), defaultdict(list)
    for entry in inventory["sets"]:
        sets[entry["id"]].append(entry)
        for card in entry["cards"]:
            for market in card["market"]:
                exact[market["productID"]].append((card, market))
            if entry.get("printRun") is not None:
                continue
            local, _ = number_parts(card.get("number"))
            if local is not None:
                by_name_and_number[normalized(card["name"]), local].append((entry, card))
    return sets, exact, by_name_and_number


def allowed_sets(group, inventory):
    group_id = group["groupId"]
    if group_id in PROMO_SETS:
        return {PROMO_SETS[group_id]}
    group_name = normalized(group["name"].split(": ", 1)[-1])
    code = normalized(group.get("abbreviation") or "")
    return {entry["id"] for entry in inventory["sets"]
            if normalized(entry["name"]) == group_name or (code and normalized(entry["code"]) == code)}


def app_candidates(product, allowed, sets, by_name_and_number):
    local, denominator = number_parts(product["number"])
    result = {}
    for name in candidate_names(product["name"]):
        for entry, card in by_name_and_number.get((name, local), []):
            if allowed and entry["id"] not in allowed:
                continue
            if denominator and denominator != str(entry.get("officialCount")):
                continue
            result[card["id"]] = card
    if allowed and not allowed.intersection(sets):
        status = "mappedSetAbsent"
    elif result:
        status = "sameSetIdentityCandidate" if allowed and len(result) == 1 else "possibleBaseIdentity"
    else:
        status = "unmatched"
    return status, [result[key] for key in sorted(result)]


def hosted_lanes(root):
    index = json.loads((root / "index.json").read_bytes())
    files = {entry["path"]: (root / entry["path"]).read_bytes() for entry in index["files"]}
    validate_site(index, files)
    lane_prices = {}
    for path, data in files.items():
        if path.endswith("/prices"):
            group = int(path.split("/")[2])
            document = json.loads(data)
            age = (instant(stamp()) - instant(document["sourceFetchedAt"])).total_seconds()
            for row in document["results"]:
                lane_prices[group, row["productId"], row["subTypeName"]] = (row.get("marketPrice"), 0 <= age < 86400)
    return index["sourceBuild"], lane_prices


def quote_state(product, expected, hosted):
    if not expected:
        return "outsideReviewedMirror"
    pid, gid = product["productID"], product["groupID"]
    states = []
    for lane in sorted(expected):
        value = hosted.get((gid, pid, lane))
        if not has_quote(product["lanes"].get(lane)):
            status = "upstreamQuoteUnavailable"
        elif value is None:
            status = "missingFromHostedFeed"
        elif not value[1]:
            status = "staleHostedQuote"
        elif not has_quote(value[0]):
            status = "hostedQuoteUnavailable"
        else:
            status = "hostedQuoteAvailable"
        states.append(f"{lane}={status}")
    return " | ".join(states)


def has_quote(value):
    return type(value) in (float, int) and math.isfinite(value) and value > 0


def compare(products, groups, inventory, scope, hosted):
    sets, exact, by_name_and_number = indexes(inventory)
    group_index = {group["groupId"]: group for group in groups}
    set_scope = {gid: allowed_sets(group, inventory) for gid, group in group_index.items()}
    rows = []
    for pid, product in products.items():
        if not product["singleCardCandidate"]:
            continue
        gid = product["groupID"]
        group = group_index[gid]
        expected = scope.get((CATEGORY, gid), {}).get(pid, set())
        matches = []
        for card, market in exact.get(pid, []):
            url = market.get("url") or ""
            lane = next(iter(parse_qs(urlsplit(url).query).get("Printing", [])), STANDARD_LANES.get(market["variant"]))
            matches.append({"appID": card["id"], "finish": market["variant"], "lane": lane,
                            "link": url, "scanFinish": market["variant"] in card["scanFinishes"],
                            "scanExactProduct": market.get("scanProductID") == pid,
                            "scanResult": card["scanResult"]})
        if matches:
            match, candidates = "exactProduct", []
        else:
            match, candidates = app_candidates(product, set_scope[gid], sets, by_name_and_number)
        unmatched_lanes = sorted(product["lanes"].keys() - {m["lane"] for m in matches})
        possible_missing_finish = False
        if len(candidates) == 1 and unmatched_lanes and product["numberSource"] == "marketField":
            exposed = {STANDARD_LANES.get(variant) for variant in candidates[0]["browseFinishes"]}
            possible_missing_finish = any(lane in STANDARD_LANES.values() and lane not in exposed
                                          for lane in unmatched_lanes)
        exact_surface_review = any(not m["link"] or (m["scanResult"] != "notTested"
                                   and not (m["scanFinish"] and m["scanExactProduct"])) for m in matches)
        rows.append({**product, "group": group["name"], "priority": is_priority(group), "match": match,
                     "unverifiedAppLanes": unmatched_lanes, "possibleMissingStandardFinish": possible_missing_finish,
                     "exactSurfaceNeedsReview": exact_surface_review,
                     "appCandidates": [{"id": c["id"], "browseFinishes": c["browseFinishes"],
                                         "scanResult": c["scanResult"], "scanFinishes": c["scanFinishes"]}
                                        for c in candidates],
                     "exactAppMatches": matches, "hostedPrice": quote_state(product, expected, hosted)})
    return rows


def catalog_changes(previous, current, incomplete_groups=()):
    previous, current = ({pid: row for pid, row in products.items() if row["groupID"] not in incomplete_groups}
                         for products in (previous, current))

    def signature(product):
        return (product["groupID"], product["name"], product["number"], product["numberSource"],
                {lane: has_quote(price) for lane, price in product["lanes"].items()})

    return {"added": sorted(current.keys() - previous.keys()), "removed": sorted(previous.keys() - current.keys()),
            "changed": sorted(pid for pid in previous.keys() & current.keys()
                              if signature(previous[pid]) != signature(current[pid]))}


def write_report(repo, capture_root, output, previous_report=None):
    captures = completed_captures(capture_root)
    if not captures:
        raise ValueError("No completed Pokémon TCGCSV capture")
    source_build, groups, products, incomplete = read_source(captures[-1])
    inventory = json.loads((output / "app-inventory.json").read_bytes())
    hosted_build, hosted = hosted_lanes(output / "hosted-prices")
    scope = scope_from_repo(repo)
    rows = compare(products, groups, inventory, scope, hosted)
    delta = None
    if len(captures) > 1:
        _, _, previous, previous_incomplete = read_source(captures[-2])
        delta = catalog_changes(previous, products, set(incomplete + previous_incomplete))
    review = [row for row in rows if "missingFromHostedFeed" in row["hostedPrice"]
              or "staleHostedQuote" in row["hostedPrice"] or (row["priority"] and (
                  row["match"] != "exactProduct" or row["unverifiedAppLanes"] or row["exactSurfaceNeedsReview"]))]
    review.sort(key=lambda row: ("missingFromHostedFeed" not in row["hostedPrice"],
                                 row["groupID"] != 1840, not row["possibleMissingStandardFinish"],
                                 not REVIEW_TREATMENT.search(row["name"]), -row["productID"]))
    by_group = defaultdict(Counter)
    for row in rows:
        by_group[row["group"]][row["match"]] += 1
    coverage_delta = None
    if previous_report is not None:
        tracked = ("match", "exactAppMatches", "appCandidates", "hostedPrice", "unverifiedAppLanes")
        previous_rows = {row["productID"]: row for row in json.loads(previous_report.read_bytes())["cards"]}
        coverage_delta = sorted(row["productID"] for row in rows if row["productID"] in previous_rows
                                and any(row.get(key) != previous_rows[row["productID"]].get(key) for key in tracked))
    summary = {"sourceBuild": source_build, "sourceDirectory": captures[-1].name, "groupCount": len(groups),
               "productCount": len(products), "singleCardCandidates": len(rows),
               "priceLanes": sum(len(product["lanes"]) for product in products.values()),
               "incompleteUpstreamGroups": incomplete, "signedCatalogRevision": inventory["revision"],
               "appSets": len(inventory["sets"]), "appCards": sum(len(entry["cards"]) for entry in inventory["sets"]),
               "hostedPriceBuild": hosted_build, "matches": dict(Counter(row["match"] for row in rows)),
               "priorityQueue": len(review), "groups": dict(by_group), "marketChanges": delta,
               "coverageChanges": coverage_delta}
    (output / "comparison.json").write_bytes(packed({"summary": summary, "cards": rows}))
    with (output / "review-queue.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(["Group", "Product ID", "Product", "Marketplace Number", "Number Evidence", "Market Lanes",
                         "Comparison", "Possible Missing Standard Finish", "Exact Surface Needs Review", "App IDs", "Scan Results",
                         "Hosted Price", "TCGplayer"])
        for row in review:
            writer.writerow([row["group"], row["productID"], row["name"], row["number"], row["numberSource"],
                             " | ".join(row["lanes"]), row["match"], row["possibleMissingStandardFinish"],
                             row["exactSurfaceNeedsReview"], " | ".join(sorted({card["id"] for card in row["appCandidates"]}
                                 | {card["appID"] for card in row["exactAppMatches"]})),
                             " | ".join(sorted({card["scanResult"] for card in row["appCandidates"] + row["exactAppMatches"]})),
                             row["hostedPrice"], f"https://www.tcgplayer.com/product/{row['productID']}"])
    (output / "summary.json").write_bytes(packed(summary))
    print(f"Compared {len(products):,} products across {len(groups)} groups with signed revision {inventory['revision']}", flush=True)
    print(f"Priority review queue has {len(review):,} entries. Reports in {output}", flush=True)


def app_fingerprint(repo):
    paths = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--",
                                     *APP_INPUTS], cwd=repo).split(b"\0")
    fingerprint = hashlib.sha256()
    for path in sorted(set(paths) - {b""}):
        file = repo / os.fsdecode(path)
        fingerprint.update(path + b"\0")
        fingerprint.update(hashlib.sha256(file.read_bytes()).digest() if file.is_file() else b"missing")
    return fingerprint.hexdigest()


def inventory_cache_path(root, output, fingerprint):
    key = hashlib.sha256(fingerprint.encode())
    for filename in ("current.json", "pokemon-catalog-snapshot.json"):
        key.update(hashlib.sha256((output / filename).read_bytes()).digest())
    return root / "app-inventory" / f"{key.hexdigest()}.json"


def export_inventory(repo, output, destination, derived_data, compiled_test, fingerprint):
    command = ["xcodebuild", "test", "-project", "TradingCardScanner.xcodeproj",
               "-scheme", "TradingCardScanner-ProfileLocal", "-derivedDataPath", str(derived_data)]
    if compiled_test is not None and compiled_test.is_file():
        proof = compiled_test.with_suffix(".sha256")
        if proof.is_file() and proof.read_text().strip() == fingerprint:
            command = ["xcodebuild", "test-without-building", "-xctestrun", str(compiled_test)]
    command += ["-destination", destination, "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                f"-only-testing:{AUDIT_TEST}", "-resultBundlePath", str(output / "inventory.xcresult")]
    environment = dict(os.environ, TEST_RUNNER_POKEMON_TCGCSV_AUDIT_ROOT=str(output))
    log = output / "xcodebuild.log"
    print(f"Exporting the app’s Scan and Browse inventory. Xcode log in {log}", flush=True)
    with log.open("wb") as file:
        result = subprocess.run(command, cwd=repo, env=environment, stdout=file, stderr=subprocess.STDOUT)
    if result.returncode or not (output / "app-inventory.json").is_file():
        raise RuntimeError(f"The app inventory test did not produce a verified export. See {log}")


def run_daily(repo, root, destination, derived_data, compiled_test):
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    with (root / "audit.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        runs = root / "runs"
        runs.mkdir(exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix=instant(stamp()).strftime("%Y%m%dT%H%M%SZ-"), dir=runs))
        source_root = root / "source"
        capture(source_root)
        stage_hosted(output)
        fingerprint = app_fingerprint(repo)
        cache = inventory_cache_path(root, output, fingerprint)
        if cache.is_file():
            shutil.copyfile(cache, output / "app-inventory.json")
            print("Reused the simulator export for the same app sources and signed catalog", flush=True)
        else:
            export_inventory(repo, output, destination, derived_data, compiled_test, fingerprint)
            if app_fingerprint(repo) != fingerprint:
                raise RuntimeError("App sources changed during the audit. Run it again for the new checkout")
            cache.parent.mkdir(exist_ok=True)
            pending = cache.with_suffix(".tmp")
            shutil.copyfile(output / "app-inventory.json", pending)
            pending.replace(cache)
        latest = root / "latest-run.txt"
        previous = runs / latest.read_text().strip() / "comparison.json" if latest.is_file() else None
        write_report(repo, source_root, output, previous)
        pending = latest.with_suffix(".tmp")
        pending.write_text(output.name + "\n")
        pending.replace(latest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    stage = commands.add_parser("stage-hosted")
    stage.add_argument("--output", type=Path, required=True)
    report = commands.add_parser("report")
    report.add_argument("--capture-root", type=Path, required=True)
    report.add_argument("--output", type=Path, required=True)
    daily = commands.add_parser("run")
    daily.add_argument("--root", type=Path, required=True)
    daily.add_argument("--destination", required=True)
    daily.add_argument("--derived-data", type=Path, required=True)
    daily.add_argument("--compiled-test", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    if args.command == "stage-hosted":
        stage_hosted(args.output)
    elif args.command == "report":
        write_report(repo, args.capture_root, args.output)
    else:
        run_daily(repo, args.root, args.destination, args.derived_data.resolve(), args.compiled_test)


if __name__ == "__main__":
    main()
