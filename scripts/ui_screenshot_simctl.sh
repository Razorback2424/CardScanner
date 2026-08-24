#!/usr/bin/env bash
set -euo pipefail

OUT_PATH="${1:-./artifacts/ui-latest.png}"
mkdir -p "$(dirname "$OUT_PATH")"
xcrun simctl io booted screenshot "$OUT_PATH"
echo "Wrote screenshot: $OUT_PATH"
