#!/usr/bin/env bash
set -euo pipefail

readonly files=(
  "TradingCardScanner/Models/CollectedCard.swift"
  "TradingCardScanner/Models/PriceRecord.swift"
  "TradingCardScanner/Models/ProductIdentity.swift"
  "TradingCardScanner/Models/CollectionActivity.swift"
  "TradingCardScanner/Models/InventoryEvent.swift"
)

failed=0
for path in "${files[@]}"; do
  printf 'Checking %s\n' "$path"
  if [[ ! -f "$path" ]]; then
    printf 'Missing synced model source: %s\n' "$path" >&2
    failed=1
    continue
  fi
  if rg -n '@Attribute\s*\(\s*\.unique|@Attribute\([^)]*\.unique|@Unique|deleteRule\s*:\s*\.deny' "$path"; then
    printf 'CloudKit-prohibited schema syntax found in %s\n' "$path" >&2
    failed=1
  fi
done

if (( failed != 0 )); then
  exit 1
fi

printf '%s\n' 'CloudKit source audit passed'
