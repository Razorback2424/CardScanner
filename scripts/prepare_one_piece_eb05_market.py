#!/usr/bin/env python3
"""Prepare a mapping-only EB-05 candidate from a verified production baseline."""

import argparse
import base64
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
import json

from market_price_feeds import digest, validate_response
from review_one_piece_base_market_mappings import base_title_matches


RELEASE = "product:bandai-series:569205"
GROUP = 24820
SOURCE = f"https://tcgcsv.com/tcgplayer/68/{GROUP}"
# The retailer product images for these six IDs were matched against Bandai
# and are pinned in the baseline's printing evidence.
SPECIAL_TITLES = {
    712885: "Nico Robin (016) (SP)",
    722774: "Gloriosa (Super Rare Alternate Art)",
    723148: "Nami (061) (Alternate Art)",
    723308: "Sugar (Super Rare Alternate Art)",
    723376: "Shirahoshi (Super Rare Alternate Art)",
    726216: "Nami (055) (Kentaro Yabuki)",
}


def prepare(release, products_raw, prices_raw, observed_at):
    products = validate_response(products_raw, 68, GROUP, "products", upstream=True)
    prices = validate_response(prices_raw, 68, GROUP, "prices", upstream=True)
    by_number = defaultdict(list)
    for product in products:
        numbers = [f["value"] for f in product.get("extendedData", []) if f["name"] == "Number"]
        if len(numbers) == 1:
            by_number[numbers[0]].append(product)
    quotes = {(row["productId"], row["subTypeName"]): row["marketPrice"] for row in prices}
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
                    or not proof.get("matchedBandaiImageSHA256") or not proof.get("retailerImageSHA256")):
                decision.update(reason="missing exact retailer artwork and finish evidence")
                continue
            retailer_id = int(proof.get("retailerReferenceProductID") or 0)
            candidates = [p for p in by_number[number] if p["productId"] == retailer_id]
            if printing["treatment"] == "Standard artwork" and alias == number:
                candidates = [p for p in candidates if base_title_matches(p["name"], name, number)]
            else:
                candidates = [p for p in candidates if SPECIAL_TITLES.get(retailer_id) == p["name"]
                              and proof.get("treatment") == printing["treatment"]]
            if len(candidates) != 1 or retailer_id in used:
                decision.update(reason="retailer product ID and exact marketplace title did not uniquely agree")
                continue
            lane = {"normal": "Normal", "foil": "Foil"}[variant]
            if (retailer_id, lane) not in quotes:
                decision.update(reason="marketplace has no exact finish lane")
                continue
            product = candidates[0]
            pid = str(retailer_id)
            oid = f'eb05-market:{printing["id"]}:{pid}:{variant}'
            detail = "Exact EB-05 number, product ID, artwork and supported finish agree with the reviewed retailer evidence."
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
                            capturedMarketPrice=quotes[retailer_id, lane])
    release["observations"].extend(new_observations)
    if new_observations:
        release["inventories"].append(dict(provider="tcgplayer", snapshotID=f"eb05-market-{observed_at}",
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
    parser.add_argument("--source-build", required=True, type=Path,
                        help="Retained TCGCSV last-updated marker, confirmed before and after the capture")
    args = parser.parse_args()
    observed = datetime.fromisoformat(args.observed_at.replace("Z", "+00:00"))
    if observed.tzinfo is None or observed > datetime.now(timezone.utc):
        parser.error("Use the actual UTC capture time")
    encoded = json.loads(args.verified_baseline.read_bytes())["payload"]
    baseline = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
    release = json.loads(baseline)
    if release["revision"] != 2:
        parser.error("Expected production revision 2")
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
