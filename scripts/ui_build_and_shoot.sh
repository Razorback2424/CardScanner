#!/usr/bin/env bash
set -euo pipefail

SCHEME="${1:?SCHEME required}"
BUNDLE_ID="${2:?BUNDLE_ID required}"
ROUTE="${3:?ROUTE required}"
STATE="${4:-}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/TradingCardScannerCodexUIBuild}"
UI_DEVICE_NAME="${UI_DEVICE_NAME:-PA Quality iPhone 17 Pro}"
UI_DEVICE_ID="${UI_DEVICE_ID:-EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-./artifacts}"
SCREENSHOT_PATH="$ARTIFACTS_DIR/ui-latest.png"
META_PATH="$ARTIFACTS_DIR/ui-latest.json"
SIMCTL=(xcrun simctl)
if [[ -n "${UI_DEVICE_SET:-}" ]]; then
  SIMCTL+=(--set "$UI_DEVICE_SET")
fi

mkdir -p "$ARTIFACTS_DIR"
"${SIMCTL[@]}" boot "$UI_DEVICE_ID" >/dev/null 2>&1 || true
"${SIMCTL[@]}" bootstatus "$UI_DEVICE_ID" -b
if [[ -n "${UI_PREBUILT_APP_PATH:-}" ]]; then
  # A caller may reuse binaries it has already built and tested. This also
  # permits visual QA when macOS file coordination blocks reopening a project.
  APP_PATH="$UI_PREBUILT_APP_PATH"
  [[ -d "$APP_PATH" ]] || { echo "Prebuilt app does not exist: $APP_PATH"; exit 1; }
else
  xcodebuild -project TradingCardScanner.xcodeproj -scheme "$SCHEME" -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" -destination "platform=iOS Simulator,id=$UI_DEVICE_ID" build
  APP_PATH="$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -type d -name "*.app" | head -n 1)"
fi
if [[ -z "${APP_PATH:-}" ]]; then
  echo "Could not find built .app under $DERIVED_DATA"
  exit 1
fi

if [[ "${UI_USE_INSTALLED_APP:-0}" != "1" ]]; then
  if [[ "${UI_PRESERVE_APP_DATA:-0}" != "1" ]]; then
    "${SIMCTL[@]}" uninstall "$UI_DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi
  "${SIMCTL[@]}" install "$UI_DEVICE_ID" "$APP_PATH"
fi
LAUNCH_ARGS=("-ui_debug_route" "$ROUTE")
if [[ -n "$STATE" ]]; then
  LAUNCH_ARGS+=("-ui_debug_state" "$STATE")
fi
if [[ "$ROUTE" == Centering* ]]; then
  CONTAINER_PATH="$("${SIMCTL[@]}" get_app_container "$UI_DEVICE_ID" "$BUNDLE_ID" data)"
  MARKER_PATH="$CONTAINER_PATH/Documents/centering-ui-ready.json"
  rm -f "$MARKER_PATH"
  LAUNCH_ARGS+=("-ui_debug_ready_path" "$MARKER_PATH")
fi
"${SIMCTL[@]}" terminate "$UI_DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
"${SIMCTL[@]}" launch "$UI_DEVICE_ID" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}"
if [[ -n "${MARKER_PATH:-}" ]]; then
  settled=0
  for _ in $(seq 1 300); do
    if [[ -f "$MARKER_PATH" ]] && rg -q 'presentedImageFrame' "$MARKER_PATH"; then
      settled=1
      break
    fi
    sleep 0.10
  done
  [[ "$settled" == "1" ]] || { echo "Centering did not settle" >&2; exit 1; }
  cp "$MARKER_PATH" "$ARTIFACTS_DIR/centering-geometry.json"
  sleep 1
else
  sleep "${UI_CAPTURE_DELAY_SECONDS:-2.5}"
fi
"$(dirname "$0")/ui_screenshot_simctl.sh" "$SCREENSHOT_PATH" "$UI_DEVICE_ID"

python3 - "$META_PATH" "$SCHEME" "$BUNDLE_ID" "$ROUTE" "$STATE" "$UI_DEVICE_ID" <<'PY'
import json, sys, time
path, scheme, bundle_id, route, state, device = sys.argv[1:]
meta = {"scheme": scheme, "bundle_id": bundle_id, "route": route, "device": device, "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S")}
if state:
    meta["state"] = state
with open(path, "w", encoding="utf-8") as handle:
    json.dump(meta, handle, indent=2)
print(json.dumps(meta, indent=2))
PY
