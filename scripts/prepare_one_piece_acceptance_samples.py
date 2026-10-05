#!/usr/bin/env python3
"""Prepare reproducible owner-review samples; never marks evidence accepted."""
import argparse
import hashlib
import json
from pathlib import Path


def samples(registry, seed="one-piece-v1-2026-10-05"):
    def order(items, identity):
        return sorted(items, key=lambda item: hashlib.sha256((seed + identity(item)).encode()).hexdigest())

    verified = {p["id"]: p for p in registry["printings"]
                if p["status"] == "verified" and p["language"] == "en"}
    cards = {c["id"]: c for c in registry["canonicalCards"]}
    groups = {product["id"]: set() for product in registry["products"]}
    for printing in verified.values():
        groups.setdefault(printing["releaseID"], set()).add(printing["id"])
    for appearance in registry["appearances"]:
        if appearance["printingID"] in verified:
            groups.setdefault(appearance["productID"], set()).add(appearance["printingID"])
    multiples = {}
    for printing in verified.values():
        multiples.setdefault(printing["canonicalCardID"], []).append(printing["id"])
    prices = [dict(mapping, printedNumber=cards[p["canonicalCardID"]]["printedNumber"])
              for p in verified.values() for mapping in p.get("marketMappings", [])
              if mapping["status"] == "exact"]
    device = []
    for family in ("ST", "OP", "EB", "P-"):
        choices = [p for p in verified.values() if cards[p["canonicalCardID"]]["printedNumber"].startswith(family)]
        device.extend(order(choices, lambda p: p["id"])[:1])
    selected = {p["id"] for p in device}
    device.extend(order([p for p in verified.values() if p["id"] not in selected], lambda p: p["id"])[:50-len(device)])
    return {
        "status": "pending-owner-review", "selectionSeed": seed,
        "registrySHA256": hashlib.sha256(json.dumps(registry, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "verifiedEnglishPrintings": len(verified),
        "groupSamples": {group: order(list(ids), lambda value: value)[:10] for group, ids in sorted(groups.items())},
        "allMultipleVerifiedPrintings": {card: sorted(ids) for card, ids in sorted(multiples.items()) if len(ids) > 1},
        "exactPriceSamples": order(prices, lambda m: m["printingID"] + m["variantID"])[:50],
        "deviceSamples": [{"printingID": p["id"], "printedNumber": cards[p["canonicalCardID"]]["printedNumber"],
                           "releaseID": p["releaseID"], "finishes": p["supportedVariantIDs"]} for p in device],
        "requiredEvidence": ["physical/official printing match", "observed provider quote and timestamp",
                             "device/OS and lighting", "read and confirm time", "offline/relaunch/recovery",
                             "VoiceOver", "peak memory and seed timing", "two-device sync and read-only preservation"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=Path, default=Path("OnePieceCatalogCore/ReviewCorpus/english-stress/registry.json"))
    parser.add_argument("--output", type=Path, required=True, help="New artifact path; existing files are retained")
    args = parser.parse_args()
    with args.output.open("x") as handle:
        json.dump(samples(json.loads(args.registry.read_text())), handle, indent=2, sort_keys=True)
        handle.write("\n")
