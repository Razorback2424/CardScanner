#!/usr/bin/env python3
"""Build reviewed early starter decks and boosters from retained standard-art captures.

Offline only. Random UUIDs are allocated once with an explicit bootstrap flag;
subsequent runs reuse the durable registry. No prices, market joins or app images.
Alternate artwork, box toppers and DON!! are outside this review's scope.
"""
import argparse
from copy import deepcopy
from datetime import date
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import uuid

from normalize_one_piece_sources import Document, one

def load_products(path):
    manifest = json.loads(path.read_text())
    if not isinstance(manifest, dict):
        raise ValueError("invalid product manifest")
    if type(manifest.get("schemaVersion")) is not int or manifest["schemaVersion"] != 1:
        raise ValueError("unsupported product manifest schema")
    products = manifest.get("products")
    if not isinstance(products, list) or not products:
        raise ValueError("missing reviewed products")
    product_ids, observation_keys = set(), set()
    date.fromisoformat(manifest["reviewDate"])
    for product in products:
        if not isinstance(product, dict):
            raise ValueError("invalid reviewed product")
        for key in ("productID", "label", "releaseDate", "prefix", "manufacturerCaptureID",
                    "manufacturerListURL", "retailerGroupID", "retailerStartURL"):
            if not isinstance(product.get(key), str) or not product[key].strip():
                raise ValueError("missing product field: " + key)
        if product["productID"] in product_ids:
            raise ValueError("duplicate product identity")
        product_ids.add(product["productID"])
        if not re.fullmatch(r"(?:OP|ST|EB|PRB)\d{2}", product["prefix"]):
            raise ValueError("invalid product prefix")
        date.fromisoformat(product["releaseDate"])
        files = product.get("retailerCaptureFiles")
        cards = product.get("cards")
        if not isinstance(files, list) or not files or len(set(files)) != len(files):
            raise ValueError("missing or duplicate retailer captures")
        if not isinstance(cards, list) or not cards:
            raise ValueError("missing reviewed card inventory")
        numbers, aliases = set(), set()
        for card in cards:
            if not isinstance(card, dict):
                raise ValueError("invalid reviewed card")
            number, alias = card.get("printedNumber"), card.get("artworkAlias")
            if not isinstance(number, str) or not re.fullmatch(r"(?:(?:OP|ST|EB|PRB)\d{2}|P)-\d{3}", number):
                raise ValueError("invalid printed number")
            if not isinstance(alias, str) or not re.fullmatch(re.escape(number) + r"(?:_p\d+)?", alias):
                raise ValueError("invalid artwork alias")
            if number in numbers or alias in aliases or type(card.get("isReprint")) is not bool:
                raise ValueError("duplicate inventory or missing reprint decision")
            numbers.add(number)
            aliases.add(alias)
            exclusions = card.get("excludedArtworkAliases", [])
            if not isinstance(exclusions, list) or alias in exclusions or len(set(exclusions)) != len(exclusions):
                raise ValueError("invalid excluded artwork aliases")
            if any(not isinstance(a, str) or not re.fullmatch(re.escape(number) + r"(?:_p\d+)?", a) for a in exclusions):
                raise ValueError("foreign excluded artwork alias")
            if "treatmentLabel" in card and (not isinstance(card["treatmentLabel"], str) or not card["treatmentLabel"].strip()):
                raise ValueError("invalid reviewed treatment label")
            key = card.get("observationKey", "launch-products:" + product["productID"] + ":" + number)
            if not isinstance(key, str) or not key.startswith("launch-products:") or key in observation_keys:
                raise ValueError("duplicate or invalid observation identity")
            observation_keys.add(key)
        finish = product.get("manufacturerFinish")
        missing_retailer = product.get("retailerEvidenceMissing", [])
        if not isinstance(missing_retailer, list) or len(set(missing_retailer)) != len(missing_retailer) or not set(missing_retailer) <= numbers:
            raise ValueError("invalid reviewed retailer evidence gap")
        excluded_listings = product.get("excludedRetailerListingPaths", [])
        if not isinstance(excluded_listings, list) or len(set(excluded_listings)) != len(excluded_listings) or any(
            not isinstance(p, str) or re.fullmatch(r"/Products/\d+/68/" + re.escape(product["retailerGroupID"]) + r"/[^?#]+", p) is None
            for p in excluded_listings
        ):
            raise ValueError("invalid reviewed retailer treatment exclusion")
        title_reviews = product.get("reviewedRetailerTitles", [])
        title_paths = set()
        if not isinstance(title_reviews, list):
            raise ValueError("invalid reviewed retailer titles")
        for review in title_reviews:
            if not isinstance(review, dict) or any(not isinstance(review.get(k), str) or not review[k].strip()
                    for k in ("listingPath", "printedNumber", "retailerTitle", "manufacturerName", "evidenceDetail")):
                raise ValueError("missing reviewed retailer title field")
            path = review["listingPath"]
            if path in title_paths or path in excluded_listings or review["printedNumber"] not in numbers or re.fullmatch(
                    r"/Products/\d+/68/" + re.escape(product["retailerGroupID"]) + r"/[^?#]+", path) is None:
                raise ValueError("invalid or duplicate reviewed retailer title")
            title_paths.add(path)
        if finish is not None:
            for key in ("captureFile", "sourceURL", "exactText", "variantID", "evidenceDetail"):
                if not isinstance(finish.get(key), str) or not finish[key].strip():
                    raise ValueError("missing manufacturer finish field: " + key)
            scope = finish.get("appliesToPrintedNumbers")
            if not isinstance(scope, list) or not scope or len(set(scope)) != len(scope) or not set(scope) <= numbers:
                raise ValueError("invalid manufacturer finish scope")
    return manifest


def capture_index(records, key):
    result = {}
    for capture in records:
        if key not in capture:
            continue
        if capture[key] in result:
            raise ValueError("duplicate capture identity: " + capture[key])
        result[capture[key]] = capture
    return result


def normalized_name(value):
    value = re.sub(r"\(\d{3}\)", "", value)
    value = unicodedata.normalize("NFKD", value)
    return "".join(c for c in value.casefold() if c.isalnum())


def names_agree(number, manufacturer, retailer):
    # Retained OP-02 retailer base listing misspells Onigumo. This exact pair is
    # reviewed; arbitrary spelling disagreements still stop reconciliation.
    if (number, manufacturer, retailer) == ("OP02-095", "Onigumo", "Oniguma"):
        return True
    # Some retailer groups append the exact printed identifier to the title.
    # Remove only that final annotation; retain treatment/stamp/revision labels.
    retailer = re.sub(r"\s*(?:\(" + re.escape(number) + r"\)|-\s*" + re.escape(number) + r")\s*$", "", retailer)
    return normalized_name(manufacturer) == normalized_name(retailer)


def reviewed_name_agrees(spec, number, manufacturer, entry):
    retailer, _, path, _ = entry
    review = next((r for r in spec.get("reviewedRetailerTitles", []) if r["listingPath"] == path), None)
    if review is not None:
        if (review["printedNumber"], review["retailerTitle"], review["manufacturerName"]) != (number, retailer, manufacturer):
            raise ValueError("reviewed retailer title changed: " + path)
        return True
    return names_agree(number, manufacturer, retailer)


def checked_capture(root, capture):
    relative = Path(capture["rawFile"])
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("unsafe capture path")
    path = root / relative
    if any((root / Path(*relative.parts[:i])).is_symlink() for i in range(1, len(relative.parts) + 1)):
        raise ValueError("symlink capture path")
    try:
        path.resolve(strict=True).relative_to(root.resolve(strict=True))
    except ValueError:
        raise ValueError("capture escapes retained root") from None
    if path.is_symlink() or path.stat().st_size > 5 * 1024 * 1024:
        raise ValueError("unsafe capture")
    data = path.read_bytes()
    if len(data) != capture["byteCount"] or hashlib.sha256(data).hexdigest() != capture["payloadSHA256"]:
        raise ValueError("capture bytes changed: " + str(path))
    return data


def review_product_evidence(spec, official, captures, official_root, capture_root, variant_ids):
    """Validate retained product inputs without allocating ownership identities."""
    prefix = spec["prefix"]
    official_id, retailer_files = spec["manufacturerCaptureID"], spec["retailerCaptureFiles"]
    source = official[official_id]
    if source["sourceURL"] != spec["manufacturerListURL"]:
        raise ValueError("manufacturer source URL changed")
    source_root = capture_root if source["rawFile"] in captures else official_root
    document = Document(checked_capture(source_root, source)).root
    selections = {c["printedNumber"]: c for c in spec["cards"]}
    expected = set(selections)
    reprints = {n for n, c in selections.items() if c["isReprint"]}
    modals = list(document.nodes("dl", "modalCol"))
    observed_aliases = {n.attrs.get("id") for n in modals}
    if any(not set(c.get("excludedArtworkAliases", [])) <= observed_aliases for c in spec["cards"]):
        raise ValueError("excluded manufacturer artwork scope changed")
    rows = {number: one([n for n in modals if n.attrs.get("id") == card["artworkAlias"]],
                       "reviewed standard artwork") for number, card in selections.items()}
    unsuffixed = {n.attrs["id"] for n in modals
                  if re.fullmatch(re.escape(prefix) + r"-\d{3}", n.attrs.get("id", ""))}
    if unsuffixed != {n for n in expected if n.startswith(prefix + "-")}:
        raise ValueError("manufacturer standard-card scope changed")
    listings = {}
    excluded_listings = set(spec.get("excludedRetailerListingPaths", []))
    observed_exclusions = set()
    for filename in retailer_files:
        capture = captures[filename]
        if filename == retailer_files[0] and capture["sourceURL"] != spec["retailerStartURL"]:
            raise ValueError("retailer source URL changed")
        retailer = Document(checked_capture(capture_root, capture)).root
        for card in retailer.nodes("div", "productCard"):
            titles = [a for a in card.nodes("a") if a.attrs.get("class") == "small"]
            if len(titles) != 1:
                continue
            title = titles[0]
            if title.attrs.get("href") in excluded_listings:
                observed_exclusions.add(title.attrs["href"])
                continue
            text = card.text(exclude={"script"})
            number = re.search(r"(?:OP|ST|EB|PRB)\d{2}-\d{3}|P-\d{3}", text)
            if not number or any(label in title.text() for label in ("Parallel", "Alternate Art", "Box Topper")):
                continue
            if number[0] not in expected:
                continue
            lanes = [n.text() for n in card.nodes("div", "small")
                     if n.text().startswith("English -")]
            if len(lanes) != 1 or re.fullmatch(r"English - (?:Near Mint|Lightly Played|Moderately Played|Heavily Played|Damaged) - (?:Normal|Foil)", lanes[0]) is None:
                raise ValueError("unreviewed retailer finish scope: " + prefix + " " + number[0] + " " + title.text() + " " + repr(lanes))
            entry = (title.text(), lanes[0], title.attrs["href"], capture)
            if any(old[2] == entry[2] for old in listings.get(number[0], [])):
                raise ValueError("duplicate retailer listing identity")
            listings.setdefault(number[0], []).append(entry)
    if observed_exclusions != excluded_listings:
        raise ValueError("reviewed retailer treatment exclusion disappeared")
    reviewed_paths = {r["listingPath"] for r in spec.get("reviewedRetailerTitles", [])}
    if not reviewed_paths <= {entry[2] for entries in listings.values() for entry in entries}:
        raise ValueError("reviewed retailer title listing disappeared")
    reviewed_missing = set(spec.get("retailerEvidenceMissing", []))
    if reviewed_missing & set(listings):
        raise ValueError("reviewed missing retailer evidence is now present; review the manifest")
    required_retailer_rows = expected - set(reprints) - reviewed_missing
    if not required_retailer_rows.issubset(listings) or not set(listings).issubset(expected):
        raise ValueError(f"retailer standard scope changed for {prefix}: missing {sorted(expected - set(listings))}, extra {sorted(set(listings) - expected)}")
    finish_spec = spec.get("manufacturerFinish")
    manufacturer_finish_capture = captures[finish_spec["captureFile"]] if finish_spec else None
    if manufacturer_finish_capture is not None:
        if finish_spec["variantID"] not in variant_ids:
            raise ValueError("unknown manufacturer finish variant")
        if manufacturer_finish_capture["sourceURL"] != finish_spec["sourceURL"]:
            raise ValueError("manufacturer finish URL changed")
        product_text = Document(checked_capture(capture_root, manufacturer_finish_capture)).root.text(exclude={"script"})
        if finish_spec["exactText"] not in product_text:
            raise ValueError("manufacturer finish specification changed")
    return source, rows, reprints, listings, finish_spec, manufacturer_finish_capture


def reconcile(registry, official_manifest, capture_manifest, official_root, capture_root, allocate, products):
    result = deepcopy(registry)
    if not any(v["id"] == "normal" for v in result["variants"]):
        result["variants"].append({"id": "normal", "label": "Normal"})
    observations, decisions = [], []
    captures = capture_index(capture_manifest["captures"], "rawFile")
    official = capture_index(official_manifest["captures"] + capture_manifest["captures"], "id")
    known = {alias["sourceID"]: p for p in result["printings"]
             for alias in p["sourceAliases"] if alias["provider"] == "bandai"}
    canonical = {c["id"]: c for c in result["canonicalCards"]}
    for spec in products:
        prefix, product_id = spec["prefix"], spec["productID"]
        label, release_date = spec["label"], spec["releaseDate"]
        source, rows, reprints, listings, finish_spec, manufacturer_finish_capture = review_product_evidence(
            spec, official, captures, official_root, capture_root, {v["id"] for v in result["variants"]})
        selections = {c["printedNumber"]: c for c in spec["cards"]}
        product = {"id": product_id, "label": label, "releaseDate": release_date}
        existing_product = next((p for p in result["products"] if p["id"] == product_id), None)
        if existing_product is None:
            result["products"].append(product)
        elif existing_product != product:
            raise ValueError("product review changed")
        for number, modal in sorted(rows.items()):
            name = one(modal.nodes(cls="cardName"), "card name").text()
            entries = listings.get(number, [])
            has_retailer_listing = bool(entries)
            if any(not reviewed_name_agrees(spec, number, name, entry) for entry in entries):
                raise ValueError("retailer/manufacturer name disagreement: " + number)
            finishes = sorted({"normal" if entry[1].endswith("Normal") else "foil" for entry in entries})
            has_manufacturer_finish = finish_spec is not None and number in finish_spec["appliesToPrintedNumbers"]
            if has_manufacturer_finish:
                finishes = sorted(set(finishes) | {finish_spec["variantID"]})
            errata = "Errata Card" in modal.text()
            status = "conflicted" if len(finishes) > 1 else "provisional" if not finishes or errata else "verified"
            supported = finishes if len(finishes) == 1 else []
            cid = "one-piece:en:" + number
            if cid not in canonical:
                c = {"id": cid, "printedNumber": number, "language": "en", "name": name,
                     "printingCoverageComplete": False}
                result["canonicalCards"].append(c)
                canonical[cid] = c
            elif canonical[cid]["name"] != name:
                raise ValueError("canonical name changed")
            alias = {"provider": "bandai", "sourceID": product_id + ":standard:" + number}
            observation_base = selections[number].get("observationKey", "launch-products:" + product_id + ":" + number)
            catalog_id, render_id = (observation_base + ":" + s for s in ("catalog", "render"))
            image = captures["images/" + modal.attrs["id"] + ".png"]
            checked_capture(capture_root, image)
            treatment = selections[number].get("treatmentLabel", "Standard artwork")
            def observation(oid, provider_alias, capture, evidence, image_hash=None):
                value = {"id": oid, "kind": "catalog", "alias": provider_alias,
                         "sourceURL": capture["sourceURL"], "observedAt": capture["observedAt"],
                         "language": "en", "payloadSHA256": capture["payloadSHA256"],
                         "productEvidence": [product_id], "printedEvidence": evidence}
                if image_hash:
                    value["imageSHA256"] = image_hash
                observations.append(value)
            observation(catalog_id, alias, source,
                        {"number": number, "name": name, "sourceArtworkAlias": modal.attrs["id"],
                         "sourceRole": "manufacturer-product-card-list", "treatment": treatment})
            observation(render_id, alias, image,
                        {"number": number, "sourceRole": "watermarked-digital-render"}, image["payloadSHA256"])
            finish_evidence = []
            for index, (listed_name, lane, listing_path, retailer_capture) in enumerate(entries):
                finish = "normal" if lane.endswith("Normal") else "foil"
                finish_id = observation_base + ":finish:" + str(index)
                printed = {"number": number, "name": listed_name, "finishVariantID": finish,
                           "sourceRole": "retailer-standard-printing-specification", "treatment": treatment}
                title_review = next((r for r in spec.get("reviewedRetailerTitles", []) if r["listingPath"] == listing_path), None)
                if title_review:
                    printed["reviewedTitleDetail"] = title_review["evidenceDetail"]
                if not lane.startswith("English - Near Mint -"):
                    printed["sourceCondition"] = lane.split(" - ")[1]
                observation(finish_id, {"provider": "coretcg", "sourceID": listing_path}, retailer_capture,
                            printed)
                finish_evidence.append({"kind": "finish", "observationID": finish_id,
                    "detail": "Retailer's exact English base-card listing specifies " + finish + "; not inferred from rarity or a photograph."})
            if has_manufacturer_finish:
                finish_id = observation_base + ":manufacturer-finish"
                observation(finish_id, alias, manufacturer_finish_capture,
                            {"number": number, "name": name, "finishVariantID": finish_spec["variantID"],
                             "sourceRole": "manufacturer-product-finish-specification", "treatment": treatment})
                finish_evidence.append({"kind": "finish", "observationID": finish_id,
                    "detail": finish_spec["evidenceDetail"]})
            existing = known.get(alias["sourceID"])
            if existing is None:
                if not allocate:
                    raise ValueError("new printing needs explicit UUID allocation: " + number)
                printing_id, artwork_id = str(uuid.uuid4()), str(uuid.uuid4())
            else:
                printing_id, artwork_id = existing["id"], existing["artworkID"]
            artwork = {"id": artwork_id, "imageSHA256": image["payloadSHA256"], "observationIDs": [render_id]}
            evidence = []
            for kind, oid, detail in (
                ("printedIdentity", catalog_id, "Manufacturer standard-art row identifies this printed number in the release."),
                ("language", catalog_id,
                 "Official English product card list; retailer independently lists English."
                 if has_retailer_listing else
                 "Official English manufacturer product card list; no matching retailer card listing was captured."),
                ("artwork", render_id, "Retained manufacturer standard-art render fingerprint; no redistribution permission implied."),
                ("release", catalog_id,
                 "Manufacturer product-scoped standard-art card list, corroborated by the retailer release listing."
                 if has_retailer_listing else
                 "Manufacturer product-scoped standard-art card list; no matching retailer card listing was captured."),
                ("treatment", catalog_id,
                 ("Product-scoped manufacturer standard reprint artwork; retailer base listing excludes parallels and box toppers."
                  if has_retailer_listing else
                  "Product-scoped manufacturer standard reprint artwork; no retailer card-level evidence was captured to corroborate parallel exclusion.")
                 if number in reprints else
                 ("Standard-art manufacturer alias without a parallel suffix; retailer base listing excludes parallels and box toppers."
                  if has_retailer_listing else
                  "Standard-art manufacturer alias without a parallel suffix; no retailer card-level evidence was captured to corroborate parallel exclusion.")),
            ):
                if kind == "treatment" and treatment != "Standard artwork":
                    detail = "Product-scoped manufacturer artwork reviewed as " + treatment + "; exact retailer title bindings retained in the product manifest."
                evidence.append({"kind": kind, "observationID": oid, "detail": detail})
            evidence.extend(finish_evidence)
            printing = {"id": printing_id, "canonicalCardID": cid, "artworkID": artwork_id,
                        "language": "en", "releaseID": product_id, "treatment": treatment,
                        "supportedVariantIDs": supported, "status": status,
                        "review": {"reference": "english-stress/starter-booster-review.json#" + (prefix + ":" if number in reprints else "") + number, "evidence": evidence},
                        "sourceAliases": [alias], "marketMappings": existing.get("marketMappings", []) if existing else [], "supersedes": []}
            if existing is None:
                result["artworks"].append(artwork)
                result["printings"].append(printing)
            elif existing != printing or next(a for a in result["artworks"] if a["id"] == artwork_id) != artwork:
                raise ValueError("existing printing review changed; requires reviewed correction")
            decisions.append({"printedNumber": number, "printingID": printing_id, "artworkID": artwork_id,
                              "releaseID": product_id, "observedFinishes": finishes, "status": status,
                              "retailerListingPaths": [entry[2] for entry in entries], "errataNotice": errata})
    inventories = [{"provider": provider, "snapshotID": "launch-products-review-2026-10-04:" + provider,
                    "paginationComplete": False,
                    "observationIDs": sorted(o["id"] for o in observations if o["alias"]["provider"] == provider)}
                   for provider in ("bandai", "coretcg")]
    return result, observations, inventories, decisions


def audit_product_sources(registry, official_manifest, capture_manifest, official_root, capture_root, products):
    """Report the whole batch's source issues without UUID allocation or adoption."""
    captures = capture_index(capture_manifest["captures"], "rawFile")
    official = capture_index(official_manifest["captures"] + capture_manifest["captures"], "id")
    variants = {v["id"] for v in registry["variants"]} | {"normal"}
    canonical = {c["id"]: c for c in registry["canonicalCards"]}
    reports = []
    for spec in products:
        report = {"productID": spec["productID"], "prefix": spec["prefix"], "issues": [],
                  "physicalCoverageComplete": False}
        try:
            _, rows, _, listings, _, _ = review_product_evidence(
                spec, official, captures, official_root, capture_root, variants)
            report["selectedRows"] = len(rows)
            report["rowsWithoutRetailerListing"] = sorted(set(rows) - set(listings))
            for number, modal in sorted(rows.items()):
                name = one(modal.nodes(cls="cardName"), "card name").text()
                for entry in listings.get(number, []):
                    if not reviewed_name_agrees(spec, number, name, entry):
                        report["issues"].append({"printedNumber": number, "reason": "retailer-manufacturer-name-disagreement",
                                                 "manufacturerName": name, "retailerName": entry[0],
                                                 "retailerListingPath": entry[2]})
                old = canonical.get("one-piece:en:" + number)
                if old and old["name"] != name:
                    report["issues"].append({"printedNumber": number, "reason": "canonical-name-change-needs-review",
                                             "retainedName": old["name"], "manufacturerName": name})
                checked_capture(capture_root, captures["images/" + modal.attrs["id"] + ".png"])
        except (ValueError, KeyError, OSError) as error:
            report["issues"].append({"reason": "retained-source-evidence-not-ready", "detail": str(error)})
        report["sourceEvidenceReady"] = not report["issues"]
        reports.append(report)
    return {"schemaVersion": 1, "purpose": "whole-batch-source-review-no-identity-allocation",
            "sourceEvidenceReady": all(r["sourceEvidenceReady"] for r in reports),
            "physicalCoverageComplete": False, "products": reports}


def discrepancy_ledger(registry, decisions, previous=None):
    """Retain reviewed history; enumerate held records without promoting them."""
    previous = previous or {"schemaVersion": 1, "discrepancies": []}
    if previous.get("schemaVersion") != 1:
        raise ValueError("unsupported discrepancy schema")
    records = deepcopy(previous["discrepancies"])
    by_id = {}
    reasons = {"missing-finish", "revision-unresolved", "release-unresolved", "artwork-unresolved",
               "source-conflict", "inventory-gap", "rights-unresolved"}
    for entry in records:
        if entry["id"] in by_id or entry["reasonCode"] not in reasons or entry["status"] not in ("open", "resolved"):
            raise ValueError("invalid or duplicate discrepancy")
        if entry["status"] == "resolved" and not entry.get("resolutionReferences"):
            raise ValueError("resolved discrepancy requires retained evidence")
        by_id[entry["id"]] = entry
    reviews = {d["printingID"]: d for d in decisions}
    canonical = {c["id"]: c for c in registry["canonicalCards"]}
    for printing in registry["printings"]:
        if printing["status"] == "verified":
            continue
        decision = reviews.get(printing["id"])
        if decision and len(decision["observedFinishes"]) > 1:
            reason, needed = "source-conflict", "Reconcile every retained normal/foil assertion against this exact physical release; do not select one retailer lane by order."
        elif printing["status"] == "conflicted":
            reason, needed = "source-conflict", "Reconcile the conflicting source evidence for this physical identity before permitting acquisition."
        elif not printing["supportedVariantIDs"]:
            reason, needed = "missing-finish", "Retain an explicit finish specification for this exact release before permitting acquisition."
            if decision and decision["errataNotice"]:
                needed += " Also reconcile the retained original/revision notice against physical evidence."
        elif decision and decision["errataNotice"]:
            reason, needed = "revision-unresolved", "Review original versus revised physical artwork/text and footer evidence; a digital Errata notice alone cannot distinguish ownership."
        else:
            reason, needed = "release-unresolved", "Retain reviewed evidence for the exact physical release and resolve its provisional status."
        identity = "printing:" + printing["id"] + ":" + reason
        references = sorted({e["observationID"] for e in printing.get("review", {}).get("evidence", [])})
        if not references:
            references = ["source-alias:" + a["provider"] + ":" + a["sourceID"] for a in printing["sourceAliases"]]
        entry = {"id": identity, "productID": printing["releaseID"],
                 "printedNumber": canonical[printing["canonicalCardID"]]["printedNumber"],
                 "sourceAliases": printing["sourceAliases"], "reasonCode": reason,
                 "evidenceReferences": references, "status": "open", "requiredEvidence": needed}
        if identity not in by_id:
            records.append(entry)
        elif by_id[identity]["status"] == "resolved":
            raise ValueError("held printing still has a resolved discrepancy; reviewed correction required")
        # Preserve the reviewer's text/references on existing open entries.
    return {"schemaVersion": 1, "discrepancies": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--capture-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--allocate-new-printings", action="store_true")
    parser.add_argument("--audit-only", action="store_true",
                        help="Report all product evidence issues; do not allocate identities or write a registry")
    args = parser.parse_args()
    product_manifest = load_products(args.products)
    original = json.loads((args.corpus / "registry.json").read_text())
    capture_manifest = json.loads((args.capture_root / "capture-manifest.json").read_text())
    official_manifest = json.loads((args.corpus / "captures.json").read_text())
    if args.audit_only:
        if args.allocate_new_printings:
            raise ValueError("source audit cannot allocate printing identities")
        audit = audit_product_sources(original, official_manifest, capture_manifest,
                                      args.capture_root.parent, args.capture_root, product_manifest["products"])
        args.output_dir.mkdir(parents=True, exist_ok=False)
        (args.output_dir / "product-source-audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
        print("Audited", len(audit["products"]), "products; no identity allocation or corpus adoption")
        if not audit["sourceEvidenceReady"]:
            raise SystemExit(1)
        return
    registry, observations, inventories, decisions = reconcile(original,
        official_manifest, capture_manifest,
        args.capture_root.parent, args.capture_root, args.allocate_new_printings, product_manifest["products"])
    ledger_path = args.corpus / "discrepancies.json"
    ledger = discrepancy_ledger(registry, decisions, json.loads(ledger_path.read_text()) if ledger_path.exists() else None)
    review = {"schemaVersion": 1, "reviewDate": product_manifest["reviewDate"], "purpose": "internal-publisher-review-not-production-assets",
              "scope": "; ".join(p["label"] for p in product_manifest["products"]) + " standard retail artwork only, including explicitly listed reprints; no parallel, box-topper, DON or event joins",
              "captures": capture_manifest["captures"], "printings": decisions,
              "physicalCoverageComplete": False, "exactMarketMappingsApproved": False,
              "productionAssetRightsEstablished": False,
              "limitations": ["Canonical printing coverage remains incomplete; explicit choice required.",
                "Rows with manufacturer errata notices remain provisional until original versus revision physical artwork/text is reconciled. Conflicting finishes remain excluded from acquisition.",
                "Standard retail release/artwork identities do not certify first-wave or footer sub-printings.",
                "Finish evidence is exact retailer product metadata or an explicitly retained manufacturer specification; never an optical inference.",
                "No prices, exact market mappings or app artwork distribution are approved."]}
    args.output_dir.mkdir(parents=True, exist_ok=False)
    for name, value in (("registry.json", registry), ("starter-booster-observations.json", observations),
                        ("starter-booster-inventories.json", inventories), ("starter-booster-review.json", review),
                        ("discrepancies.json", ledger)):
        (args.output_dir / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    print(f"Reviewed {len(decisions)} standard release/artwork identities; retained {len(original['printings'])} earlier UUIDs")


if __name__ == "__main__":
    main()
