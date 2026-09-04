#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_directory="${MAGIC_TREATMENT_SNAPSHOT_OUTPUT:-$project_root/TradingCardScanner/MagicTreatmentSnapshot}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/magic-treatment-snapshot.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

bulk_data_response="$temporary_directory/bulk-data.json"
bulk_data_file="$temporary_directory/default-cards.json"

echo "Fetching Scryfall bulk-data metadata..."
curl --fail --location --silent --show-error \
    https://api.scryfall.com/bulk-data \
    --output "$bulk_data_response"

bulk_data_id="$(/usr/bin/python3 - "$bulk_data_response" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
record = next(item for item in payload["data"] if item["type"] == "default_cards")
print(record["id"])
PY
)"
bulk_data_type="$(/usr/bin/python3 - "$bulk_data_response" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
record = next(item for item in payload["data"] if item["type"] == "default_cards")
print(record["type"])
PY
)"
download_uri="$(/usr/bin/python3 - "$bulk_data_response" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
record = next(item for item in payload["data"] if item["type"] == "default_cards")
print(record.get("jsonl_download_uri") or record.get("download_uri") or "")
PY
)"
updated_at="$(/usr/bin/python3 - "$bulk_data_response" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
record = next(item for item in payload["data"] if item["type"] == "default_cards")
print(record.get("updated_at", ""))
PY
)"

if [[ -z "$download_uri" ]]; then
    echo "Scryfall did not publish a download URI for default_cards." >&2
    exit 1
fi

if [[ "$bulk_data_type" != "default_cards" ]]; then
    echo "Scryfall returned an unexpected bulk-data type: $bulk_data_type" >&2
    exit 1
fi

echo "Downloading Scryfall default_cards bulk data..."
curl --fail --location --silent --show-error \
    "$download_uri" \
    --output "$temporary_directory/default-cards-download"
if [[ "$download_uri" == *.gz ]]; then
    gzip -dc "$temporary_directory/default-cards-download" > "$bulk_data_file"
else
    cp "$temporary_directory/default-cards-download" "$bulk_data_file"
fi
content_sha256="$(shasum -a 256 "$bulk_data_file" | awk '{print $1}')"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

echo "Generating the committed Magic treatment audit snapshot..."
generator_binary="$temporary_directory/magic-treatment-snapshot-generator"
xcrun swiftc -D DEBUG \
    "$project_root/TradingCardScanner/Services/MagicTreatmentSnapshot.swift" \
    "$project_root/scripts/magic_treatment_snapshot_generator.swift" \
    -o "$generator_binary"
MAGIC_TREATMENT_SNAPSHOT_INPUT="$bulk_data_file" \
MAGIC_TREATMENT_SNAPSHOT_OUTPUT="$output_directory" \
MAGIC_TREATMENT_SNAPSHOT_BULK_ID="$bulk_data_id" \
MAGIC_TREATMENT_SNAPSHOT_BULK_TYPE="$bulk_data_type" \
MAGIC_TREATMENT_SNAPSHOT_DOWNLOAD_URI="$download_uri" \
MAGIC_TREATMENT_SNAPSHOT_UPDATED_AT="$updated_at" \
MAGIC_TREATMENT_SNAPSHOT_SHA256="$content_sha256" \
MAGIC_TREATMENT_SNAPSHOT_GENERATED_AT="$generated_at" \
"$generator_binary"

echo "Generating the compact runtime Magic treatment catalog..."
"$project_root/scripts/generate_magic_treatment_catalog.sh" \
    "$output_directory" \
    "$project_root/TradingCardScanner/MagicTreatmentCatalog"

echo "Magic treatment snapshot written to $output_directory"
echo "Magic treatment catalog written to $project_root/TradingCardScanner/MagicTreatmentCatalog"
