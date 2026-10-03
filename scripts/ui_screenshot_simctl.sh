#!/usr/bin/env bash
set -euo pipefail

OUT_PATH="${1:-./artifacts/ui-latest.png}"
DEVICE_ID="${2:-booted}"
mkdir -p "$(dirname "$OUT_PATH")"
SIMCTL=(xcrun simctl)
if [[ -n "${UI_DEVICE_SET:-}" ]]; then
  SIMCTL+=(--set "$UI_DEVICE_SET")
fi
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ui-screenshot.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
# CoreSimulator's screenshot service may lack removable-volume permission.
# Stage this small capture in system temporary storage, then move it to the
# caller's preferred artifact location.
"${SIMCTL[@]}" io "$DEVICE_ID" screenshot --type=png "$STAGING_DIR/screenshot.png"
mv "$STAGING_DIR/screenshot.png" "$OUT_PATH"
echo "Wrote screenshot: $OUT_PATH"
