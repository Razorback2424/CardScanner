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
if [[ -n "${UI_CONTENT_SIZE_CATEGORY:-}" ]]; then
  LAUNCH_ARGS+=("-UIPreferredContentSizeCategoryName" "$UI_CONTENT_SIZE_CATEGORY")
fi
if [[ -n "${UI_APP_LOCALE:-}" ]]; then
  LAUNCH_ARGS+=("-AppleLocale" "$UI_APP_LOCALE")
fi
if [[ "$ROUTE" == Centering* ]]; then
  CONTAINER_PATH="$("${SIMCTL[@]}" get_app_container "$UI_DEVICE_ID" "$BUNDLE_ID" data)"
  if [[ -n "${UI_CENTERING_FIXTURE_SOURCE:-}" ]]; then
    UI_CENTERING_FIXTURE_PATH="$CONTAINER_PATH/Documents/centering-ui-input.${UI_CENTERING_FIXTURE_SOURCE##*.}"
    cp "$UI_CENTERING_FIXTURE_SOURCE" "$UI_CENTERING_FIXTURE_PATH"
  fi
  if [[ -n "${UI_CENTERING_PRECISION_ACTIONS_SOURCE:-}" ]]; then
    UI_CENTERING_PRECISION_ACTIONS_PATH="$CONTAINER_PATH/Documents/centering-ui-actions.json"
    cp "$UI_CENTERING_PRECISION_ACTIONS_SOURCE" "$UI_CENTERING_PRECISION_ACTIONS_PATH"
  fi
  if [[ -n "${UI_CENTERING_FIXTURE_PATH:-}" ]]; then
    LAUNCH_ARGS+=("-ui_debug_fixture_path" "$UI_CENTERING_FIXTURE_PATH")
  fi
  if [[ -n "${UI_CENTERING_PRECISION_ACTIONS_PATH:-}" ]]; then
    LAUNCH_ARGS+=("-ui_debug_precision_actions_path" "$UI_CENTERING_PRECISION_ACTIONS_PATH")
  fi
  if [[ "${UI_CENTERING_CONFIRM_FRAMES:-0}" == "1" ]]; then
    LAUNCH_ARGS+=("-ui_debug_confirm_frames")
  fi
  if [[ -n "${UI_CENTERING_PHOTO_ROTATION:-}" ]]; then
    LAUNCH_ARGS+=("-ui_debug_photo_rotation" "$UI_CENTERING_PHOTO_ROTATION")
  fi
  if [[ "${UI_CENTERING_RESET_PHOTO_ROTATION:-0}" == "1" ]]; then
    LAUNCH_ARGS+=("-ui_debug_reset_photo_rotation")
  fi
  MARKER_PATH="$CONTAINER_PATH/Documents/centering-ui-ready.json"
  MARKER_PATTERN='presentedImageFrame'
  MARKER_ARTIFACT='centering-geometry.json'
elif [[ "$ROUTE" == "PricingSettingsReview" || "$ROUTE" == "StorageSettingsReview" ]]; then
  CONTAINER_PATH="$("${SIMCTL[@]}" get_app_container "$UI_DEVICE_ID" "$BUNDLE_ID" data)"
  MARKER_PATH="$CONTAINER_PATH/Documents/settings-ui-ready.json"
  MARKER_PATTERN='settingsReviewReady'
  MARKER_ARTIFACT='settings-ready.json'
elif [[ "$ROUTE" == "YuGiOhHistoryReview" || ( "$ROUTE" == "CardDetail" && "$STATE" == price-chart* ) ]]; then
  CONTAINER_PATH="$("${SIMCTL[@]}" get_app_container "$UI_DEVICE_ID" "$BUNDLE_ID" data)"
  MARKER_PATH="$CONTAINER_PATH/Documents/card-price-history-ui-ready.json"
  MARKER_PATTERN='marketHistoryReady'
  MARKER_ARTIFACT='market-history-ready.json'
elif [[ "$ROUTE" == "OnePieceAcceptance" ]]; then
  CONTAINER_PATH="$("${SIMCTL[@]}" get_app_container "$UI_DEVICE_ID" "$BUNDLE_ID" data)"
  MARKER_PATH="$CONTAINER_PATH/Documents/one-piece-ui-ready.json"
  MARKER_PATTERN='onePieceAcceptanceReady'
  MARKER_ARTIFACT='one-piece-ready.json'
elif [[ "$ROUTE" == "YuGiOhAcceptance" && -n "$STATE" ]]; then
  CONTAINER_PATH="$("${SIMCTL[@]}" get_app_container "$UI_DEVICE_ID" "$BUNDLE_ID" data)"
  MARKER_PATH="$CONTAINER_PATH/Documents/yugioh-ui-ready.json"
  MARKER_PATTERN='yuGiOhAcceptanceReady'
  MARKER_ARTIFACT='yugioh-ready.json'
elif [[ "$ROUTE" == "LorcanaReview" || "$ROUTE" == "LorcanaPricingReview" ]]; then
  CONTAINER_PATH="$("${SIMCTL[@]}" get_app_container "$UI_DEVICE_ID" "$BUNDLE_ID" data)"
  MARKER_PATH="$CONTAINER_PATH/Documents/lorcana-ui-ready.json"
  MARKER_PATTERN='lorcanaReviewReady'
  MARKER_ARTIFACT='lorcana-ready.json'
fi
if [[ -n "${MARKER_PATH:-}" ]]; then
  rm -f "$MARKER_PATH"
  LAUNCH_ARGS+=("-ui_debug_ready_path" "$MARKER_PATH")
fi
"${SIMCTL[@]}" terminate "$UI_DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
"${SIMCTL[@]}" launch "$UI_DEVICE_ID" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}"
if [[ -n "${MARKER_PATH:-}" ]]; then
  settled=0
  for _ in $(seq 1 300); do
    if [[ -f "$MARKER_PATH" ]] && rg -q "$MARKER_PATTERN" "$MARKER_PATH"; then
      settled=1
      break
    fi
    sleep 0.10
  done
  [[ "$settled" == "1" ]] || { echo "$ROUTE did not settle" >&2; exit 1; }
  if [[ -n "${UI_CENTERING_EXPECTED_SHA256:-}" ]]; then
    python3 - "$MARKER_PATH" "$UI_CENTERING_EXPECTED_SHA256" <<'PY'
import json, sys
record = json.load(open(sys.argv[1]))
if record.get("inputSHA256") != sys.argv[2]:
    raise SystemExit("The rendered input hash does not match the requested development image")
PY
  fi
  cp "$MARKER_PATH" "$ARTIFACTS_DIR/$MARKER_ARTIFACT"
  sleep "${UI_CAPTURE_DELAY_SECONDS:-1}"
else
  sleep "${UI_CAPTURE_DELAY_SECONDS:-2.5}"
fi
"$(dirname "$0")/ui_screenshot_simctl.sh" "$SCREENSHOT_PATH" "$UI_DEVICE_ID"
if [[ -n "${MARKER_PATH:-}" && -f "$MARKER_PATH" ]]; then
  cp "$MARKER_PATH" "$ARTIFACTS_DIR/$MARKER_ARTIFACT"
  python3 - "$MARKER_PATH" "$ARTIFACTS_DIR" <<'PY'
import json, shutil, sys
from pathlib import Path
marker = json.loads(Path(sys.argv[1]).read_text())
source = marker.get("exportFilePath")
if source and Path(source).is_file():
    shutil.copyfile(source, Path(sys.argv[2]) / "actual-model-export.png")
PY
fi

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
