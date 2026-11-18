#!/usr/bin/env python3
"""Certify One Piece card families whose complete physical printing universe is documented.

A certified card is marked ``printingCoverageComplete``. That removes it from
Browse's "Partial catalog" rule and lets the scanner choose its only verified
printing automatically, so certification is strict and evidence-bound.

``report`` compares every canonical card in an unsigned candidate with:

* the complete English Bandai card list, as an ``audit_one_piece_coverage.py``
  report produced for that exact candidate across every series, and
* a complete TCGCSV category 68 daily snapshot (every group's products).

A card is certifiable when every Bandai presentation of its number is a
verified printing, every active printing is verified or known but never priced
on TCGplayer (see ``known_unpriced``), no Browse discovery
remains, every source observation for the number is reconciled to exactly one
printing, and every same-number TCGplayer product is accounted for. Edit only
``resolutions`` in the generated report. A resolution covers one unaccounted
TCGplayer product of one card::

    "resolutions": {"one-piece:en:OP01-001": {"454999": {
        "decision": "exclude" | "same-printing", "printingID": "<only for same-printing>",
        "reason": "...", "citation": "https://..."}}}

``certify`` repeats the comparison against the same bound inputs, applies the
resolutions, and writes reviewed additions for
``audit_one_piece_coverage.py --reviewed-additions``. The audit re-checks the
structural gates and drops a certification again when Bandai later lists a new
presentation of that number.
"""

import argparse
import base64
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

from audit_one_piece_coverage import BROWSE_DISCOVERY, known_unpriced
from capture_one_piece_products import atomic_json
from one_piece_tcgcsv_capture import TCGCSVSnapshot
from reconcile_one_piece_retail_printings import listing_treatment


REFERENCE_PREFIX = "one-piece-coverage-certification:"
GROUPS_URL = "https://tcgcsv.com/tcgplayer/68/groups"
COREPATH = re.compile(r"/Products/[1-9][0-9]*/68/([1-9][0-9]*)/")
COREID = re.compile(r"([1-9][0-9]*):[1-9][0-9]*")


def load_release(path):
    payload = path.read_bytes()
    release = json.loads(payload)
    if "payload" in release:
        payload = base64.urlsafe_b64decode(release["payload"] + "===")
        release = json.loads(payload)
    return release, hashlib.sha256(payload).hexdigest()


def load_market(directory):
    """Replay a complete retained TCGCSV snapshot; return its build and numbered products."""
    market = TCGCSVSnapshot(directory, "CardScannerOnePieceReview/1.0", 0.15, offline=True)
    if market.manifest.get("complete") is not True or market.manifest.get("upstreamBuild") != market.upstream_build:
        raise ValueError("Coverage certification requires a complete retained daily TCGCSV snapshot")
    groups = market.fetch_json(GROUPS_URL)["results"]
    products = defaultdict(list)
    for group in groups:
        document = market.fetch_json(f"https://tcgcsv.com/tcgplayer/68/{group['groupId']}/products")
        if document.get("sourceInventoryComplete") is False:
            raise ValueError("TCGCSV group export is incomplete: " + str(group["groupId"]))
        for row in document["results"]:
            numbers = [field["value"] for field in row.get("extendedData", []) if field["name"] == "Number"]
            if len(numbers) == 1:
                products[numbers[0]].append({"productId": row["productId"], "groupId": row["groupId"],
                                             "name": row["name"], "groupName": group["name"]})
    market.finish()
    return market.upstream_build, products


def market_claims(registry, observations):
    """TCGplayer products that a printing's own reviewed evidence or mapping names."""
    claims = defaultdict(set)
    for printing in registry["printings"]:
        for mapping in printing["marketMappings"]:
            if mapping["provider"] == "tcgplayer":
                claims[int(mapping["productID"])].add(printing["id"])
        for evidence in (printing.get("review") or {}).get("evidence", []):
            reference = observations[evidence["observationID"]]["printedEvidence"].get("retailerReferenceProductID")
            if reference is not None:
                claims[int(reference)].add(printing["id"])
    return claims


def group_releases(registry):
    """Marketplace groups whose reviewed printings all belong to one release."""
    releases = defaultdict(set)
    for printing in registry["printings"]:
        if printing.get("releaseID") is None:
            continue
        groups = {str(mapping.get("qualifiers", {}).get("groupID")) for mapping in printing["marketMappings"]
                  if mapping["provider"] == "tcgplayer" and mapping.get("qualifiers", {}).get("groupID")}
        for alias in printing["sourceAliases"]:
            if alias["provider"] == "coretcg":
                match = COREID.fullmatch(alias["sourceID"]) or COREPATH.match(alias["sourceID"])
                if match:
                    groups.add(match[1])
        for group in groups:
            releases[int(group)].add(printing["releaseID"])
    return {group: next(iter(ids)) for group, ids in releases.items() if len(ids) == 1}


def treatment_key(value):
    return None if value in (None, "", "Standard artwork") else value


def compare_cards(release, coverage, market_products):
    registry = release["registry"]
    observations = {row["id"]: row for row in release["observations"]}
    printings_by_card = defaultdict(list)
    for printing in registry["printings"]:
        if printing["status"] != "superseded":
            printings_by_card[printing["canonicalCardID"]].append(printing)
    registered = {}
    for printing in registry["printings"]:
        for alias in printing["sourceAliases"]:
            registered[(alias["provider"], alias["sourceID"])] = printing["id"]
    evidence_printings = defaultdict(set)
    for printing in registry["printings"]:
        for evidence in (printing.get("review") or {}).get("evidence", []):
            alias = observations[evidence["observationID"]]["alias"]
            evidence_printings[(alias["provider"], alias["sourceID"])].add(printing["id"])
    observations_by_card = defaultdict(list)
    for row in release["observations"]:
        number = row["printedEvidence"].get("number")
        if row["kind"] == "catalog" and number:
            observations_by_card[f"one-piece:{row['language']}:{number}"].append(row)
    official = defaultdict(list)
    for series in coverage["series"]:
        for row in series["rows"]:
            if row["number"]:
                official["one-piece:en:" + row["number"]].append(
                    {"series": series["seriesID"], "alias": row["artworkAlias"], "status": row["status"],
                     "printingIDs": row["printingIDs"]})
    claims = market_claims(registry, observations)
    releases_by_group = group_releases(registry)

    cards = {}
    for card in registry["canonicalCards"]:
        card_id, number = card["id"], card["printedNumber"]
        printings = printings_by_card[card_id]
        printing_ids = {row["id"] for row in printings}
        blockers, attachments = [], {}
        if not printings:
            blockers.append("no-active-printing")
        # A known printing TCGplayer never priced does not leave the family open;
        # it stays uncollectable and excludes the card from automatic selection.
        unpriced = {row["id"] for row in printings if known_unpriced(row, observations)}
        blockers += [f"printing-not-verified:{row['id']}:{row['status']}" for row in printings
                     if row["status"] != "verified" and row["id"] not in unpriced]
        rows = official[card_id]
        if not rows:
            blockers.append("no-official-bandai-presentation")
        blockers += [f"official-presentation-{row['status']}:{row['series']}/{row['alias']}" for row in rows
                     if row["status"] != "verified"
                     and not (row["status"] == "held" and set(row["printingIDs"]) <= unpriced)]
        for row in observations_by_card[card_id]:
            alias = (row["alias"]["provider"], row["alias"]["sourceID"])
            if row["printedEvidence"].get("sourceRole") == BROWSE_DISCOVERY:
                blockers.append("browse-discovery:" + row["id"])
            elif alias in registered:
                continue
            elif len(evidence_printings[alias]) == 1 and evidence_printings[alias] <= printing_ids:
                attachments[alias] = next(iter(evidence_printings[alias]))
            else:
                blockers.append("unreconciled-source-observation:" + row["id"])
        accounted, unaccounted, by_title = {}, [], defaultdict(list)
        claimed_here = {owner for product in market_products.get(number, [])
                        for owner in claims.get(product["productId"], set()) & printing_ids}
        for product in sorted(market_products.get(number, []), key=lambda row: row["productId"]):
            owners = claims.get(product["productId"], set()) & printing_ids
            if len(owners) == 1:
                accounted[str(product["productId"])] = next(iter(owners))
                continue
            release_id = releases_by_group.get(product["groupId"])
            treatment = listing_treatment(number, card["name"], product["name"])
            matches = [row["id"] for row in printings if release_id is not None
                       and row.get("releaseID") == release_id and treatment is not None
                       and treatment_key(row.get("treatment")) == treatment_key(treatment[1])
                       and not row.get("distributionLabel") and not row.get("stamp")]
            if not owners and len(matches) == 1 and matches[0] not in claimed_here:
                by_title[matches[0]].append(product)
            else:
                unaccounted.append(product)
        # A title match is only an identity when one product claims that printing.
        for printing_id, products in by_title.items():
            if len(products) == 1:
                accounted[str(products[0]["productId"])] = printing_id
            else:
                unaccounted += products
        unaccounted = [{"productID": str(row["productId"]), "name": row["name"], "groupID": row["groupId"],
                        "groupName": row["groupName"]} for row in sorted(unaccounted, key=lambda row: row["productId"])]
        cards[card_id] = {"number": number, "name": card["name"], "knownUnpricedPrintingIDs": sorted(unpriced),
                          "printingIDs": sorted(printing_ids), "officialPresentations": rows,
                          "blockers": sorted(set(blockers)),
                          "aliasAttachments": [{"printingID": owner, "alias": {"provider": a[0], "sourceID": a[1]}}
                                               for a, owner in sorted(attachments.items())],
                          "accountedMarketProducts": accounted, "unaccountedMarketProducts": unaccounted,
                          "sourceObservationIDs": sorted(row["id"] for row in observations_by_card[card_id])}
    return cards


def resolved(card, resolutions):
    """Return remaining unaccounted products after reviewed resolutions, rejecting stale ones."""
    open_products = {row["productID"] for row in card["unaccountedMarketProducts"]}
    for product_id, resolution in resolutions.items():
        if product_id not in open_products:
            raise ValueError(f"Resolution names an accounted or unknown product: {product_id}")
        decision = resolution.get("decision")
        citation = urlsplit(resolution.get("citation", ""))
        if (decision not in {"exclude", "same-printing"} or not str(resolution.get("reason", "")).strip()
                or citation.scheme != "https" or not citation.netloc):
            raise ValueError(f"Resolution needs a decision, reason and https citation: {product_id}")
        if decision == "same-printing" and resolution.get("printingID") not in card["printingIDs"]:
            raise ValueError(f"Resolution names a printing outside this card: {product_id}")
        if decision == "exclude" and "printingID" in resolution:
            raise ValueError(f"An exclusion cannot name a printing: {product_id}")
    return open_products - set(resolutions)


def status(card, resolutions=None):
    if card["blockers"]:
        return "blocked"
    remaining = resolved(card, resolutions or {})
    return "needs-resolution" if remaining else "certifiable"


def bound_inputs(args):
    release, release_sha = load_release(args.release)
    coverage_bytes = args.coverage.read_bytes()
    coverage = json.loads(coverage_bytes)
    if coverage.get("payloadSHA256") != release_sha:
        raise ValueError("The coverage report was produced for a different candidate")
    if coverage.get("requestedSeries"):
        raise ValueError("Certification requires a coverage report across every Bandai series")
    referenced = {urlsplit(row["sourceURL"]).query for row in release["observations"]
                  if row["alias"]["provider"] == "bandai" and urlsplit(row["sourceURL"]).path == "/cardlist/"}
    audited = {"series=" + series["seriesID"] for series in coverage["series"]}
    missing = sorted(query for query in referenced if query.startswith("series=") and query not in audited)
    if missing:
        raise ValueError("The coverage report omits Bandai series referenced by the candidate: " + ", ".join(missing))
    build, products = load_market(args.market_captures)
    bindings = {"releasePayloadSHA256": release_sha,
                "coverageSHA256": hashlib.sha256(coverage_bytes).hexdigest(),
                "tcgcsvUpstreamBuild": build}
    return release, compare_cards(release, coverage, products), bindings


def report_command(args):
    if args.output.exists():
        raise ValueError("Certification report already exists")
    _, cards, bindings = bound_inputs(args)
    counts = Counter(status(card) for card in cards.values())
    reasons = Counter(blocker.split(":")[0] for card in cards.values() for blocker in card["blockers"])
    atomic_json(args.output, {"schemaVersion": 1, "bindings": bindings, "counts": dict(sorted(counts.items())),
                              "blockerCounts": dict(sorted(reasons.items())), "resolutions": {},
                              "cards": {key: dict(card, status=status(card)) for key, card in sorted(cards.items())}})
    print(dict(sorted(counts.items())))


def certify_command(args):
    if args.output.exists():
        raise ValueError("Reviewed additions already exist")
    report_bytes = args.report.read_bytes()
    report = json.loads(report_bytes)
    release, cards, bindings = bound_inputs(args)
    if report.get("bindings") != bindings:
        raise ValueError("The report was generated from different candidate, coverage or marketplace inputs")
    resolutions = report.get("resolutions", {})
    if set(resolutions) - cards.keys():
        raise ValueError("Resolutions name unknown canonical cards")
    certified = sorted(key for key, card in cards.items() if status(card, resolutions.get(key)) == "certifiable")
    reference = REFERENCE_PREFIX + hashlib.sha256(report_bytes).hexdigest()
    attachments = [row for key in certified for row in cards[key]["aliasAttachments"]]
    providers = {row["id"]: row["alias"]["provider"] for row in release["observations"]}
    by_provider = defaultdict(set)
    for key in certified:
        for observation_id in cards[key]["sourceObservationIDs"]:
            by_provider[providers[observation_id]].add(observation_id)
    # Each provider's source rows for the certified families were enumerated
    # against the complete Bandai and marketplace inventories bound in the report.
    inventories = [{"provider": provider, "snapshotID": reference, "paginationComplete": True,
                    "observationIDs": sorted(ids)} for provider, ids in sorted(by_provider.items())]
    atomic_json(args.output, {"artworks": [], "printings": [], "observations": [], "inventories": inventories,
                              "aliasAttachments": attachments,
                              "coverageCertifications": [{"canonicalCardID": key, "reference": reference}
                                                         for key in certified]})
    print(f"Certified {len(certified)} of {len(cards)} canonical cards")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("report", "certify"):
        command = commands.add_parser(name)
        command.add_argument("--release", type=Path, required=True, help="Unsigned candidate or verified envelope")
        command.add_argument("--coverage", type=Path, required=True,
                             help="audit_one_piece_coverage.py report for this exact candidate, all series")
        command.add_argument("--market-captures", type=Path, required=True,
                             help="Complete retained TCGCSV category 68 snapshot with every group's products")
        command.add_argument("--output", type=Path, required=True)
        if name == "certify":
            command.add_argument("--report", type=Path, required=True, help="Reviewed certification report")
    args = parser.parse_args()
    (report_command if args.command == "report" else certify_command)(args)


if __name__ == "__main__":
    main()
