#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swiftc "$repo/TradingCardScanner/Games/Core/LoadOnce.swift" \
  "$repo/TradingCardScanner/Games/YuGiOh/YuGiOhReleaseWire.swift" \
  "$repo/TradingCardScanner/Games/YuGiOh/YuGiOhCatalog.swift" \
  "$repo/scripts/yugioh_catalog_publisher.swift" -o "${1:?Provide the output binary path}"
