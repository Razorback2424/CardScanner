#!/usr/bin/env python3
"""Reconcile retained all-era name pages and a reviewed Exodus front batch.

This builds dated receipts; it never enables production acquisition. Current
automatic lookup/save additionally requires a bounded provider collision check.
"""
import argparse
import hashlib
import json
from datetime import date, timedelta
from pathlib import Path
from build_magic_historical_index import canonical_title, digest, validate_page


def build(args):
    original = args.index.read_bytes()
    artifact = json.loads(original)
    review = json.loads(args.review.read_text())
    if review["reviewKind"] not in {"provider_front_visible_number", "printed_front_visible_number"} or review["reviewedOn"] != args.observed_on.isoformat():
        raise ValueError("dated printed-front review required")
    reviewed = {row["printingID"]: row for row in review["records"]}
    if len(reviewed) != len(review["records"]):
        raise ValueError("duplicate reviewed printing")
    indexed = {row["printingID"]: row for row in artifact["records"]}
    for printing_id, front in reviewed.items():
        if printing_id not in indexed or front.get("imageKind", "provider_front") not in {"provider_front", "photographic_front"}:
            raise ValueError("review identity or image kind unsupported")
        if indexed[printing_id]["setCode"] != "exo" or front.get("denominator") != 143:
            raise ValueError("only the reviewed Exodus template is supported")
        if canonical_title(front["name"]) != canonical_title(indexed[printing_id]["name"]):
            raise ValueError("review printing name mismatch")
    pages = {}
    captures = []
    names = sorted(set(["Allay", "Cataclysm", "Monstrous Hound", "Angelic Blessing", "Charging Paladin"])
                   | {row["name"] for row in reviewed.values()})
    for name in names:
        path = args.captures / (name.replace(" ", "-") + "-search.json")
        rows = validate_page(json.loads(path.read_text()))
        if any(canonical_title(row["name"]) != canonical_title(name) or row.get("lang") != "en"
               or "paper" not in row.get("games", []) for row in rows.values()):
            raise ValueError("search response does not match its exact English/paper evidence scope")
        pages[name] = rows
        captures.append({"name": name, "sha256": digest(path), "resultCount": len(rows)})
    discrepancies = []
    for record in artifact["records"]:
        provider = pages.get(record["name"], {}).get(record["printingID"])
        if provider is None and not record["reconciled"]:
            direct = args.captures / (record["printingID"] + ".json")
            provider = json.loads(direct.read_text())
            captures.append({"printingID": record["printingID"], "sha256": digest(direct)})
        if provider is None:
            continue
        if provider["id"] != record["printingID"] or provider["collector_number"] != record["collectorNumber"]:
            raise ValueError("exact printing/collector crosswalk changed")
        set_row = next(row for row in artifact["catalog"]["sets"] if row["code"].lower() == record["setCode"])
        if provider["set_id"] != set_row["scryfallSetID"] or provider["set"] != record["setCode"]:
            raise ValueError("exact set crosswalk changed")
        source_language = {"English": "en", "Spanish": "es"}.get(record["language"], record["language"])
        if provider["lang"] != source_language:
            discrepancies.append({"printingID": record["printingID"], "kind": "language_conflict",
                                  "sourceLanguage": record["language"], "providerLanguage": provider["lang"]})
            record["unresolvedDistinctions"] = ["source_language_conflict"]
            # Keep the contradictory row as a blocker; an English result filter
            # cannot silently remove an unreconciled identity from the family.
            continue
        if provider.get("object") != "card" or provider.get("digital") is not False or provider.get("oversized") is not False:
            raise ValueError("unsupported or malformed physical printing")
        if canonical_title(provider["name"]) != canonical_title(record["name"]):
            raise ValueError("exact printing name changed")
        if provider["layout"] != record["layout"] or set(provider["finishes"]) != set(record["finishes"]):
            raise ValueError("layout/finish crosswalk disagreement")
        if provider["released_at"] != record["releaseDate"]:
            discrepancies.append({"printingID": record["printingID"], "kind": "printing_date_correction",
                                  "sourceSetDate": record["releaseDate"], "printingDate": provider["released_at"]})
        record.update(reconciled=True, language=source_language, setID=provider["set_id"], oracleID=provider["oracle_id"],
                      releaseDate=provider["released_at"], artworkID=provider.get("illustration_id"),
                      thumbnailURL=provider.get("image_uris", {}).get("small"),
                      paper="paper" in provider["games"])
        day = date.fromisoformat(record["releaseDate"])
        record["route"] = "modernFooter" if day >= date(2014, 7, 18) else (
            "legacyCollectorNumber" if day >= date(1998, 6, 15) else "legacyNoCollectorNumber")
        record["unresolvedDistinctions"] = ["physical_review_pending"]
        if record["printingID"] in reviewed:
            front = reviewed[record["printingID"]]
            if front["collectorNumber"] != record["collectorNumber"] or front["layout"] != record["layout"]:
                raise ValueError("front review identity mismatch")
            filename = front.get("imageFilename", record["name"].replace(" ", "-") + ".jpg")
            if Path(filename).name != filename or not filename.endswith(".jpg"):
                raise ValueError("review image must be a local JPEG filename")
            image = args.captures / filename
            if digest(image) != front["imageSHA256"]:
                raise ValueError("reviewed front changed")
            record["visibleCollectorNumber"] = True
            record["unresolvedDistinctions"] = []
            if front.get("imageKind", "provider_front") == "provider_front":
                front["imageURL"] = provider["image_uris"]["large"]
    capture_manifest = {"observedOn": args.observed_on.isoformat(), "captures": captures,
                        "frontReviewSHA256": digest(args.review)}
    capture_bytes = (json.dumps(capture_manifest, sort_keys=True, separators=(",", ":")) + "\n").encode()
    source_hash = hashlib.sha256(capture_bytes).hexdigest()
    artifact["sources"] = [source for source in artifact["sources"] if source["kind"] != "scryfallCrossEra"]
    artifact["sources"].append({"kind": "scryfallCrossEra", "url": "https://api.scryfall.com/cards/search",
                                "sha256": source_hash, "dataDate": args.observed_on.isoformat()})
    complete = []
    receipts = []
    keys = {(canonical_title(row["name"]), row["collectorNumber"].lower()) for row in artifact["records"]}
    for printing_id, front in reviewed.items():
        matches = [row for row in artifact["records"] if canonical_title(row["name"]) == canonical_title(front["name"])
                   and row["collectorNumber"] == front["collectorNumber"]]
        current_ids = {row["id"] for row in pages[front["name"]].values() if row["collector_number"] == front["collectorNumber"]}
        indexed_ids = {row["printingID"] for row in matches}
        if current_ids != indexed_ids or any(not row["reconciled"] for row in matches):
            discrepancies.append({"printingID": printing_id, "kind": "incomplete_current_key",
                                  "providerIDs": sorted(current_ids), "indexIDs": sorted(indexed_ids)})
            continue
        key = {"title": canonical_title(front["name"]), "collectorNumber": front["collectorNumber"]}
        complete.append(key)
        receipts.append({"key": key, "sourceSHA256": source_hash, "printingIDs": sorted(current_ids),
                         "pageCount": 1, "resultCount": len(current_ids), "reconciliationVersion": 1})
    complete.sort(key=lambda key: (key["title"], key["collectorNumber"]))
    receipts.sort(key=lambda receipt: (receipt["key"]["title"], receipt["key"]["collectorNumber"]))
    complete_set = {(key["title"], key["collectorNumber"]) for key in complete}
    artifact["coverage"] = {"completeKeys": complete, "keyReceipts": receipts,
        "unresolvedKeys": [dict(title=title, collectorNumber=number) for title, number in sorted(keys - complete_set)],
        "validUntil": (args.observed_on + timedelta(days=1)).isoformat() + "T00:00:00.000Z" if complete else None,
        "sourceContext": source_hash, "missingSources": []}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "cross-era-capture.json").write_bytes(capture_bytes)
    output = args.output / "pilot-index.json"
    output.write_text(json.dumps(artifact, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
    report = {"observedOn": args.observed_on.isoformat(), "inputIndexSHA256": hashlib.sha256(original).hexdigest(),
        "artifactSHA256": digest(output), "artifactBytes": output.stat().st_size,
        "sourceContext": source_hash, "reviewedFronts": list(reviewed.values()), "discrepancies": discrepancies,
        "completeKeyCount": len(complete), "reconciledPrintingCount": sum(row["reconciled"] for row in artifact["records"]),
        "productionEnabled": False, "deviceAcceptance": "pending"}
    (args.output / "review-reconciliation-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--captures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--observed-on", type=date.fromisoformat, required=True)
    print(json.dumps(build(parser.parse_args()), sort_keys=True))


if __name__ == "__main__":
    main()
