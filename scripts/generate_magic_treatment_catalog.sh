#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
audit_directory="${1:-$project_root/TradingCardScanner/MagicTreatmentSnapshot}"
output_directory="${2:-$project_root/TradingCardScanner/MagicTreatmentCatalog}"

/usr/bin/python3 - "$audit_directory" "$output_directory" <<'PY'
import json
import pathlib
import sys

audit_directory = pathlib.Path(sys.argv[1])
output_directory = pathlib.Path(sys.argv[2])
manifest_path = audit_directory / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

known_signals = {"surgefoil", "neonink"}
manual_colors = {
    card["cardID"]: card["value"]
    for mapping in manifest.get("manualMappings", [])
    for card in mapping["cards"]
    if mapping.get("treatment", "").lower() == "neonink"
}

entries = []
seen_ids = set()
for set_entry in manifest["entries"]:
    resource = set_entry.get("resource")
    if not resource:
        continue
    resource_path = audit_directory / resource
    for card in json.loads(resource_path.read_text(encoding="utf-8")):
        signals = {
            signal.lower()
            for signal in card.get("promoTypes", []) + card.get("frameEffects", [])
        }
        treatments = sorted(known_signals.intersection(signals))
        if not treatments:
            continue
        card_id = card["id"]
        if card_id in seen_ids:
            raise SystemExit(f"Duplicate treatment catalog card id: {card_id}")
        seen_ids.add(card_id)
        entry = {
            "id": card_id,
            "setCode": card["setCode"],
            "collectorNumber": card["collectorNumber"],
            "treatments": treatments,
        }
        if card_id in manual_colors:
            if "neonink" not in treatments:
                raise SystemExit(
                    f"Manual Neon Ink mapping is not a Neon Ink card: {card_id}"
                )
            entry["qualifiers"] = {"neonink": manual_colors[card_id]}
        entries.append(entry)

for card_id in manual_colors:
    if card_id not in seen_ids:
        raise SystemExit(f"Manual mapping is absent from treatment catalog: {card_id}")

entries.sort(key=lambda entry: entry["id"])
source = manifest["source"]
artifact = {
    "schemaVersion": 2,
    "sourceAuditSchemaVersion": manifest["schemaVersion"],
    "sourceAuditRulesVersion": manifest["rulesVersion"],
    "sourceBulkDataID": source["bulkDataID"],
    "sourceBulkDataType": source["bulkDataType"],
    "sourceContentSHA256": source["contentSHA256"],
    "generatedAt": manifest["generatedAt"],
    "entries": entries,
}

output_directory.mkdir(parents=True, exist_ok=True)
output_path = output_directory / "manifest.json"
output_path.write_text(
    json.dumps(artifact, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
print(f"Magic treatment catalog written to {output_path} ({len(entries)} entries)")
PY
