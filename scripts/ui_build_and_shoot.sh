#!/usr/bin/env bash
set -euo pipefail

SCHEME="${1:?SCHEME required}"
BUNDLE_ID="${2:?BUNDLE_ID required}"
ROUTE="${3:?ROUTE required}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/TradingCardScannerCodexUIBuild}"
UI_DEVICE_NAME="${UI_DEVICE_NAME:-PA Quality iPhone 16 Pro}"
UI_DEVICE_ID="${UI_DEVICE_ID:-B22E024C-1288-43AC-85AE-BB26B1010F64}"
ARTIFACTS_DIR="./artifacts"
SCREENSHOT_PATH="$ARTIFACTS_DIR/ui-latest.png"
META_PATH="$ARTIFACTS_DIR/ui-latest.json"

mkdir -p "$ARTIFACTS_DIR"
xcrun simctl boot "$UI_DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UI_DEVICE_ID" -b
xcodebuild -project TradingCardScanner.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" -destination "platform=iOS Simulator,id=$UI_DEVICE_ID" build

APP_PATH="$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -type d -name "*.app" | head -n 1)"
if [[ -z "${APP_PATH:-}" ]]; then
  echo "Could not find built .app under $DERIVED_DATA"
  exit 1
fi

xcrun simctl uninstall "$UI_DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UI_DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$UI_DEVICE_ID" "$BUNDLE_ID" -ui_debug_route "$ROUTE"
sleep 2.5
"$(dirname "$0")/ui_screenshot_simctl.sh" "$SCREENSHOT_PATH" "$UI_DEVICE_ID"

python3 - "$META_PATH" "$SCHEME" "$BUNDLE_ID" "$ROUTE" <<'PY'
import json, sys, time
path, scheme, bundle_id, route = sys.argv[1:]
meta = {"scheme": scheme, "bundle_id": bundle_id, "route": route, "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S")}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(meta, handle, indent=2)
print(json.dumps(meta, indent=2))
PY
