#!/usr/bin/env python3
"""Prepare a mapping-only PRB02 candidate from a verified production baseline."""

import argparse
import base64
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
import json

from market_price_feeds import digest, validate_response
from reconcile_one_piece_retail_printings import listing_treatment


RELEASE = "product:prb02-premium-booster-the-best-vol-2-2025"
GROUP = 24305
SOURCE = f"https://tcgcsv.com/tcgplayer/68/{GROUP}"
def reviewed_title_matches(product_name, retailer_title, name, number, treatment):
    """Require both independent titles to identify the reviewed treatment."""
    retailer = listing_treatment(number, name, retailer_title)
    market = listing_treatment(number, name, product_name)
    return retailer is not None and retailer == market and retailer[1] == treatment


def prepare(release, products_raw, prices_raw, observed_at):
    products = validate_response(products_raw, 68, GROUP, "products", upstream=True)
    prices = validate_response(prices_raw, 68, GROUP, "prices", upstream=True)
    by_number = defaultdict(list)
    for product in products:
        numbers = [f["value"] for f in product.get("extendedData", []) if f["name"] == "Number"]
        if len(numbers) == 1:
            by_number[numbers[0]].append(product)
    quotes = defaultdict(list)
    for row in prices:
        quotes[row["productId"], row["subTypeName"]].append(row["marketPrice"])
    registry = release["registry"]
    cards = {row["id"]: row for row in registry["canonicalCards"]}
    printings = {row["id"]: row for row in registry["printings"]}
    observations = {row["id"]: row for row in release["observations"]}
    appearances = {row["printingID"] for row in registry["appearances"] if row["productID"] == RELEASE}
    report = []
    new_observations = []
    discoveries = defaultdict(set)
    for observation in observations.values():
        evidence = observation["printedEvidence"]
        if RELEASE in observation["productEvidence"] and evidence.get("sourceRole") == "manufacturer-browse-discovery":
            discoveries[evidence["number"]].add(evidence["sourceArtworkAlias"])
    used = {int(mapping["productID"]) for printing in registry["printings"]
            for mapping in printing["marketMappings"] if mapping["provider"] == "tcgplayer"
            and mapping["status"] == "exact" and mapping["qualifiers"].get("groupID") == str(GROUP)}
    references = Counter()
    for printing in printings.values():
        if printing.get("releaseID") == RELEASE and not printing["marketMappings"]:
            for evidence in printing["review"]["evidence"]:
                if evidence["kind"] == "finish":
                    reference = observations[evidence["observationID"]]["printedEvidence"].get("retailerReferenceProductID")
                    if reference:
                        references[reference] += 1
    for printing in printings.values():
        if printing.get("releaseID") != RELEASE and printing["id"] not in appearances:
            continue
        card = cards[printing["canonicalCardID"]]
        name, number = card["name"], card["printedNumber"]
        for variant in printing["supportedVariantIDs"]:
            existing = [m for m in printing["marketMappings"] if m["variantID"] == variant]
            decision = dict(name=name, number=number, artworkID=printing["artworkID"],
                            printingID=printing["id"], finish=variant, treatment=printing.get("treatment"),
                            printingStatus=printing["status"], existingMappings=existing, status="held")
            report.append(decision)
            if existing:
                decision.update(status="existing")
                continue
            if (printing["status"] != "verified" or printing["language"] != "en"
                    or printing.get("releaseID") != RELEASE or printing.get("stamp")
                    or printing.get("distributionLabel")):
                decision.update(reason="requires separate review of exact release and presentation")
                continue
            finish = next((observations[e["observationID"]] for e in printing["review"]["evidence"]
                           if e["kind"] == "finish"), None)
            proof = finish["printedEvidence"] if finish else {}
            alias = proof.get("sourceArtworkAlias")
            if (proof.get("sourceRole") != "retailer-exact-printing-specification"
                    or proof.get("finishVariantID") != variant
                    or proof.get("number") != number
                    or not alias or not proof.get("matchedBandaiImageSHA256") or not proof.get("retailerImageSHA256")):
                decision.update(reason="missing exact retailer artwork and finish evidence")
                continue
            retailer_id = int(proof.get("retailerReferenceProductID") or 0)
            candidates = [p for p in by_number[number] if p["productId"] == retailer_id]
            candidates = [p for p in candidates if proof.get("treatment") == printing["treatment"]
                          and reviewed_title_matches(p["name"], proof.get("retailerTitle", ""),
                                                     name, number, printing["treatment"])]
            if len(candidates) != 1 or retailer_id in used or references[str(retailer_id)] != 1:
                decision.update(reason="retailer product ID and exact marketplace title did not uniquely agree")
                continue
            lane = {"normal": "Normal", "foil": "Foil"}[variant]
            if len(quotes[retailer_id, lane]) != 1:
                decision.update(reason="marketplace has no unique exact finish lane")
                continue
            product = candidates[0]
            pid = str(retailer_id)
            oid = f'prb02-market:{printing["id"]}:{pid}:{variant}'
            detail = "Exact PRB02 number, product ID, artwork and supported finish agree with the reviewed retailer evidence."
            qualifiers = dict(groupID=str(GROUP), productName=product["name"], finish=lane)
            fields = dict(number=number, marketProductID=pid, marketVariantID=lane, finishVariantID=variant,
                          market="us", currency="USD", condition="aggregate", treatment=printing["treatment"],
                          retailerEvidenceID=finish["id"], sourcePricePayloadSHA256=digest(prices_raw))
            fields.update({f"qualifier:{key}": value for key, value in qualifiers.items()})
            new_observations.append(dict(id=oid, kind="market", alias=dict(provider="tcgplayer", sourceID=pid),
                                         sourceURL=f"{SOURCE}/products", observedAt=observed_at, language="en",
                                         payloadSHA256=digest(products_raw), productEvidence=[RELEASE], printedEvidence=fields))
            mapping = dict(printingID=printing["id"], provider="tcgplayer", productID=pid,
                           providerVariantID=lane, variantID=variant, market="us", currency="USD",
                           condition="aggregate", qualifiers=qualifiers, status="exact",
                           review=dict(reference=f"{SOURCE}/products#{pid}", evidence=[
                               dict(kind=kind, observationID=oid, detail=detail)
                               for kind in ("printedIdentity", "marketIdentity")]))
            printing["marketMappings"].append(mapping)
            used.add(retailer_id)
            decision.update(status="exact", mapping=mapping, retailerEvidenceID=finish["id"],
                            capturedMarketPrice=quotes[retailer_id, lane][0])
    release["observations"].extend(new_observations)
    if new_observations:
        release["inventories"].append(dict(provider="tcgplayer", snapshotID=f"prb02-market-{observed_at}",
                                           paginationComplete=False,
                                           observationIDs=sorted(o["id"] for o in new_observations)))
    verified_aliases = defaultdict(set)
    for decision in report:
        printing = printings[decision["printingID"]]
        if printing["status"] == "verified":
            for evidence in printing["review"]["evidence"]:
                alias = observations[evidence["observationID"]]["printedEvidence"].get("sourceArtworkAlias")
                if alias:
                    verified_aliases[decision["number"]].add(alias)
    names = {card["printedNumber"]: card["name"] for card in cards.values()}
    return dict(baselineRevision=release["revision"], verifiedPrintingFinishes=report,
                discoveryEntries=[dict(name=names.get(number), number=number, artworkAliases=sorted(aliases),
                                       verifiedNumberOverlap=number in verified_aliases,
                                       verifiedAliasOverlap=sorted(aliases & verified_aliases[number]),
                                       status="printing review required")
                                  for number, aliases in sorted(discoveries.items())])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("verified-baseline", "products", "prices", "output"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    parser.add_argument("--observed-at", required=True)
    parser.add_argument("--baseline-revision", type=int, choices=(3, 4), default=3)
    parser.add_argument("--source-build", required=True, type=Path,
                        help="Retained TCGCSV last-updated marker, confirmed before and after the capture")
    args = parser.parse_args()
    observed = datetime.fromisoformat(args.observed_at.replace("Z", "+00:00"))
    if observed.tzinfo is None or observed > datetime.now(timezone.utc):
        parser.error("Use the actual UTC capture time")
    encoded = json.loads(args.verified_baseline.read_bytes())["payload"]
    baseline = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
    release = json.loads(baseline)
    if release["revision"] != args.baseline_revision:
        parser.error("Production baseline revision does not match the requested revision")
    products, prices = args.products.read_bytes(), args.prices.read_bytes()
    report = prepare(release, products, prices, args.observed_at)
    report.update(productsSHA256=digest(products), pricesSHA256=digest(prices),
                  baselineEnvelopeSHA256=digest(args.verified_baseline.read_bytes()), observedAt=args.observed_at,
                  sourceBuild=args.source_build.read_text().strip())
    args.output.mkdir()
    (args.output / "baseline.json").write_bytes(baseline)
    for name, value in [("gap-report", report), *((key, release[key]) for key in ("registry", "observations", "inventories"))]:
        (args.output / f"{name}.json").write_text(json.dumps(value, indent=2) + "\n")


if __name__ == "__main__":
    main()
