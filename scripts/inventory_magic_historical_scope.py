#!/usr/bin/env python3
"""Inventory existing set descriptors. This is not a physical-printing importer."""
import argparse
import csv
import hashlib
import json
from datetime import date
from pathlib import Path

VERSION = 1
EXODUS = date(1998, 6, 15)
MODERN = date(2014, 7, 18)


def disposition(row):
    if row.get("routingKind") or row["setType"] in {"token", "memorabilia", "minigame", "art_series"}:
        return "special_or_child", "separate content/layout review required"
    if not row["browseEnabled"]:
        return "browse_excluded", "descriptor excludes Browse; paper eligibility unproven"
    try:
        released = date.fromisoformat(row["releaseDate"])
        if released.isoformat() != row["releaseDate"]:
            return "uncertain_date", "missing or invalid release date"
    except (KeyError, TypeError, ValueError):
        return "uncertain_date", "missing or invalid release date"
    if released < EXODUS:
        return "phase_2", "pre-Exodus; visible number not established"
    if released >= MODERN:
        return "outside_phase_1", "modern interval; existing scanning policy retained"
    return "phase_1_review_lead", "set date only; printing/paper/English/visible-number/layout evidence missing"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reviewed-on", type=date.fromisoformat, required=True)
    args = parser.parse_args()
    raw = args.input.read_bytes()
    catalog = json.loads(raw)
    if catalog["schemaVersion"] != 1 or catalog["catalogKind"] != "magic":
        raise ValueError("expected existing Magic schema 1 descriptors")
    sets = catalog["sets"]
    if len({row["scryfallSetID"] for row in sets}) != len(sets):
        raise ValueError("duplicate set identity")
    if len({row["code"].strip().lower() for row in sets}) != len(sets):
        raise ValueError("duplicate set code")
    args.output.mkdir(parents=True, exist_ok=True)
    counts = {}
    inventory = args.output / "set-review-inventory.csv"
    with inventory.open("w", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(["set_id", "code", "name", "release_date", "set_type", "browse_enabled",
                         "modern_scan_enabled", "disposition", "reason"])
        for row in sorted(sets, key=lambda row: row["code"].lower()):
            state, reason = disposition(row)
            counts[state] = counts.get(state, 0) + 1
            writer.writerow([row["scryfallSetID"], row["code"], row["displayName"], row.get("releaseDate", ""),
                             row["setType"], str(row["browseEnabled"]).lower(),
                             str(row["scanEnabled"]).lower(), state, reason])
    manifest = {
        "processingVersion": VERSION,
        "reviewedOn": args.reviewed_on.isoformat(),
        "input": "TradingCardScanner/MagicCatalogSeed/catalog.json",
        "inputSHA256": hashlib.sha256(raw).hexdigest(),
        "inputGeneratedAt": catalog["generatedAt"],
        "inputRevision": catalog["revision"],
        "inputSchemaVersion": catalog["schemaVersion"],
        "inventorySHA256": hashlib.sha256(inventory.read_bytes()).hexdigest(),
        "countsBySetDisposition": counts,
        "physicalPrintingDenominator": None,
        "printingReconciliation": "not performed",
        "liveDirectoryContext": "not captured",
        "source": "existing bundled seed; no new provider download",
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")


if __name__ == "__main__":
    main()
