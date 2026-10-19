#!/usr/bin/env python3
"""Install only MEE output from the recorded-fixture Swift checklist builder.

Run PokemonTCGCSVPriceTests/testReviewedEnergyProductsAndChecklistRegenerationPreserveOldRows
first, then pass its MEE_GENERATED_CHECKLIST directory. --check is read-only.
The authoring inputs remain publisher/fixtures/mee-*.json and the reviewed
PokemonTCGCSVMapping; this script never invents checklist rows.
"""
import argparse
import json
from pathlib import Path


def fingerprint(text):
    value = 14695981039346656037
    for byte in text.encode():
        value = ((value ^ byte) * 1099511628211) & ((1 << 64) - 1)
    return format(value, "x")


def set_id(entry):
    value = entry["set"]["catalogID"]
    identity = f'{value["game"]}:{value["providerID"].lower()}'
    if value.get("pokemonPrintRun"):
        identity += f':{value["pokemonPrintRun"]}'
    return identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("generated", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    target = root / "TradingCardScanner/PokemonChecklistSnapshot"
    original = json.loads((target / "manifest.json").read_text())
    generated = json.loads((args.generated / "manifest.json").read_text())
    assert generated["schemaVersion"] == generated["rulesVersion"] == 1
    assert len(generated["entries"]) == 1
    new = generated["entries"][0]
    assert new["providerID"] == "mee"
    old = next(e for e in original["entries"] if e["providerID"] == "mee")
    old_rows = json.loads((target / old["resource"]).read_text())
    new_bytes = (args.generated / new["resource"]).read_bytes()
    new_rows = json.loads(new_bytes)
    assert [r for r in new_rows if r["providerID"].startswith("mee-")] == [
        r for r in old_rows if r["providerID"].startswith("mee-")]
    assert len(new_rows) == new["standardSlotCount"] == new["expandedSlotCount"] == 24
    assert new["set"]["cardCount"] == 24
    assert new["officialCount"] == 8
    assert {r["collectorNumber"] for r in new_rows} == {f"{n:03}" for n in range(1, 17)}
    evidence = json.loads((root / "publisher/fixtures/mee-reviewed-products.json").read_text())
    products = {p["productId"]: p for p in evidence["products"]["results"]}
    for row in new_rows:
        if not row["providerID"].startswith("tcgplayer:"):
            continue
        product = products[int(row["providerID"].split(":")[1])]
        assert product["groupId"] == 24461
        assert next(f["value"] for f in product["extendedData"] if f["name"] == "Number") == row["collectorNumber"]
        assert row["masterSetVariant"]["id"] == "holo"
        assert row["imageURL"] == product["imageUrl"]
    if args.check:
        assert old == new
        assert json.loads((target / new["resource"]).read_bytes()) == new_rows
        print("MEE generated snapshot matches: 16 numbers, 24 slots; primary rows preserved")
        return
    original["entries"] = [new if e["providerID"] == "mee" else e for e in original["entries"]]
    # Match the Swift schema-1 decoder: a legacy fingerprint without the probe
    # field is not a signed canonical provider fingerprint.
    original["directoryFingerprint"] = fingerprint("\x1f".join(
        f'{set_id(e)}={e.get("providerFingerprint") or "<legacy>"}'
        if "providerProbeFingerprint" in e else f'{set_id(e)}=<legacy>'
        for e in sorted(original["entries"], key=set_id)))
    original["generatedAt"] = generated["generatedAt"]
    destination = target / new["resource"]
    destination.write_bytes(new_bytes)
    (target / "manifest.json").write_text(json.dumps(original, separators=(",", ":")) + "\n")
    if old["resource"] != new["resource"]:
        (target / old["resource"]).unlink()
    print("Installed generated MEE checklist; all other manifest entries and resources preserved")


if __name__ == "__main__":
    main()
