#!/usr/bin/env python3
"""Build a review crosswalk from retained source products, never ownership joins."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re

from build_one_piece_catalog import write_output
from one_piece_tcgcsv_capture import validate_document


def reconcile(catalog_path, capture_dir, official_path):
    catalog_bytes = catalog_path.read_bytes()
    catalog = json.loads(catalog_bytes)
    captures = json.loads((capture_dir / "captures.json").read_bytes())
    official = json.loads(official_path.read_bytes())
    if catalog["meta"]["category_id"] != 68 or captures.get("complete") is not True:
        raise ValueError("Expected a completed retained category-68 response capture")
    if catalog["meta"]["upstream_build"] != captures["upstreamBuild"]:
        raise ValueError("Catalog and raw snapshot use different upstream builds")
    targets = sorted({o["printedEvidence"]["number"] for o in official})
    if any(re.fullmatch(r"[A-Z][A-Z0-9]*-\d{3}", n) is None for n in targets):
        raise ValueError("Expected numbered official review scope")
    observations, inventories, crosswalk = [], [], []
    by_capture = defaultdict(list)
    raw_groups = {}
    for number in targets:
        products = [r for r in catalog["cards"] if r["printed_card_number"] == number]
        for row in products:
            gid, pid = row["tcgplayer_group_id"], row["tcgplayer_product_id"]
            url = f"https://tcgcsv.com/tcgplayer/68/{gid}/products"
            record = captures["captures"][url]
            if gid not in raw_groups:
                expected_file = f"68-{gid}-products.json"
                if record["rawFile"] != expected_file:
                    raise ValueError("Unexpected retained source path")
                raw = (capture_dir / expected_file).read_bytes()
                if len(raw) != record["byteCount"] or hashlib.sha256(raw).hexdigest() != record["payloadSHA256"]:
                    raise ValueError("Retained product bytes changed")
                raw_groups[gid] = {p["productId"]: p for p in validate_document(json.loads(raw), url)["results"]}
            source = raw_groups[gid][pid]
            fields = {f["name"]: f["value"] for f in source.get("extendedData", [])}
            if source["name"] != row["product_name"] or fields.get("Number") != number:
                raise ValueError("Generated row does not match retained source product")
            identity = f"tcgplayer:{pid}:{record['payloadSHA256']}"
            observations.append({"id": identity, "kind": "market",
                "alias": {"provider": "tcgplayer", "sourceID": str(pid)}, "sourceURL": url,
                "observedAt": record["observedAt"], "language": "unknown",
                "payloadSHA256": record["payloadSHA256"], "productEvidence": [f"tcgplayer-group:{gid}"],
                "printedEvidence": {"number": number, "sourceProductName": row["product_name"],
                    "sourceGroupLabel": row["group_name"], "sourceVariantClass": row["variant_class"],
                    "sourceVariantLabels": ",".join(row["variant_labels"]),
                    "marketProductURL": row["tcgplayer_url"], "referenceImageURL": row["image_url"]}})
            by_capture[url].append(identity)
        crosswalk.append({"number": number,
            "bandaiArtworkAliases": sorted({o["alias"]["sourceID"] for o in official
                if o["alias"]["provider"] == "bandai" and o["printedEvidence"]["number"] == number}),
            "candidateMarketProducts": [{"productID": r["tcgplayer_product_id"], "name": r["product_name"],
                "groupID": r["tcgplayer_group_id"], "groupLabel": r["group_name"]} for r in products],
            "reviewedPhysicalJoins": [], "physicalCoverageComplete": False})
    for url, ids in sorted(by_capture.items()):
        inventories.append({"provider": "tcgplayer", "snapshotID": f"tcgcsv:{captures['captures'][url]['payloadSHA256']}:stress-subset",
                            "paginationComplete": False, "observationIDs": sorted(ids)})
    return {"observations": sorted(observations, key=lambda r: r["id"]), "inventories": inventories,
        "crosswalk": {"schemaVersion": 1, "generatedFromCatalogSHA256": hashlib.sha256(catalog_bytes).hexdigest(),
                      "upstreamBuild": captures["upstreamBuild"], "rows": crosswalk}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--capture-dir", type=Path, required=True)
    parser.add_argument("--official-observations", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    result = reconcile(args.catalog, args.capture_dir, args.official_observations)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, value in result.items():
        write_output(args.output_dir / f"tcgcsv-{name}.json", json.dumps(value, indent=2, sort_keys=True) + "\n")
    print(f"Retained {len(result['observations'])} market observations; no physical joins allocated")


if __name__ == "__main__": main()
