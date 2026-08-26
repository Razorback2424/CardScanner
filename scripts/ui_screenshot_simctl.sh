#!/usr/bin/env bash
set -euo pipefail

OUT_PATH="${1:-./artifacts/ui-latest.png}"
DEVICE_ID="${2:-booted}"
mkdir -p "$(dirname "$OUT_PATH")"
xcrun simctl io "$DEVICE_ID" screenshot "$OUT_PATH"
echo "Wrote screenshot: $OUT_PATH"
