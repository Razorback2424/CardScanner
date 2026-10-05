#!/usr/bin/env bash
set -euo pipefail

# Run from any directory. This is the final architecture gate, including legacy
# branches still pending extraction; it is intentionally strict.
task_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
central_files=(
  "$task_root/TradingCardScanner/Services/BrowseCatalog.swift"
  "$task_root/TradingCardScanner/Services/CardScanner.swift"
  "$task_root/TradingCardScanner/Services/CardCatalog.swift"
  "$task_root/TradingCardScanner/Services/PriceQuoteService.swift"
  "$task_root/TradingCardScanner/Services/CollectionCatalogNormalizer.swift"
)
# This lexical gate catches explicit game branches; arbitrary default blocks
# still require review because Swift's inferred switch type is not available here.
game='\.(pokemon|magic|onePiece|lorcana)'
pattern="^[[:space:]]*case([[:space:]]+let)?[[:space:]]+$game(:|[^A-Za-z0-9_:].*:)|[!=]=[[:space:]]*$game([^A-Za-z0-9_]|$)|$game[[:space:]]*[!=]=|^[[:space:]]*default:.*unsupportedGame"
if matches="$(rg --no-heading --line-number --color never "$pattern" "${central_files[@]}")"; then
  printf '%s\n' 'Game boundary audit failed: move game-specific cases behind game adapters.' >&2
  printf '%s\n' "$matches" >&2
  exit 1
else
  status=$?
  if [[ "$status" != 1 ]]; then
    printf '%s\n' 'Game boundary audit could not read all designated central files.' >&2
    exit "$status"
  fi
fi
printf '%s\n' 'Game boundary audit passed.'
