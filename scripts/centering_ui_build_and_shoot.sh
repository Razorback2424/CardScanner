#!/usr/bin/env bash
set -euo pipefail

FIXTURE_NAME="${1:?fixture name required, for example IMG_0347}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_ID="${UI_DEVICE_ID:-EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86}"
BUNDLE_ID="${UI_BUNDLE_ID:-com.seankeller.CardScanner}"
DERIVED_DATA="${DERIVED_DATA:-/tmp/TradingCardScannerCenteringUIBuild}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/review/centering-evidence/after}"
FIXTURE_SOURCE="$REPO_ROOT/TestFixtures/TradingCards/HEIC/$FIXTURE_NAME.HEIC"
SCREENSHOT_PATH="$EVIDENCE_DIR/screenshots/${FIXTURE_NAME}_CenteringExpanded.png"
MARKER_NAME="centering-${FIXTURE_NAME}.json"

if [[ ! -f "$FIXTURE_SOURCE" ]]; then
    echo "Missing fixture: $FIXTURE_SOURCE" >&2
    exit 1
fi

mkdir -p "$EVIDENCE_DIR/screenshots" "$EVIDENCE_DIR/metadata"
xcrun simctl boot "$DEVICE_ID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_ID" -b

xcodebuild -project "$REPO_ROOT/TradingCardScanner.xcodeproj" \
    -scheme TradingCardScanner \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    build

APP_PATH="$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -type d -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
    echo "Could not find the built app under $DERIVED_DATA" >&2
    exit 1
fi

xcrun simctl uninstall "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
CONTAINER_PATH="$(xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data)"
FIXTURE_PATH="$CONTAINER_PATH/Documents/$FIXTURE_NAME.HEIC"
MARKER_PATH="$CONTAINER_PATH/Documents/$MARKER_NAME"

xcrun simctl spawn "$DEVICE_ID" /bin/mkdir -p "$CONTAINER_PATH/Documents"
xcrun simctl spawn "$DEVICE_ID" /bin/rm -f "$MARKER_PATH" "$FIXTURE_PATH"
# simctl spawn executes inside the simulator, so the test fixture stays out of
# the app bundle while the debug route still exercises the real Data importer.
xcrun simctl spawn "$DEVICE_ID" /bin/sh -c "/bin/cat > '$FIXTURE_PATH'" < "$FIXTURE_SOURCE"

xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID" \
    -ui_debug_route CenteringExpanded \
    -ui_debug_fixture_path "$FIXTURE_PATH" \
    -ui_debug_ready_path "$MARKER_PATH" >/dev/null

settled=0
for _ in $(seq 1 300); do
    # The marker is written when analysis settles. The frame field is appended
    # by the rendered view, so waiting for it also proves the screenshot will
    # contain the same fitted image rect used by the guide overlay.
    if xcrun simctl spawn "$DEVICE_ID" /bin/sh -c "/usr/bin/grep -q 'presentedImageFrame' '$MARKER_PATH'" >/dev/null 2>&1; then
        settled=1
        break
    fi
    sleep 0.10
done
if [[ "$settled" != 1 ]]; then
    echo "Timed out waiting for centering analysis: $FIXTURE_NAME" >&2
    exit 1
fi

xcrun simctl io "$DEVICE_ID" screenshot "$SCREENSHOT_PATH"
# Keep tracked evidence below the plan's 1.5 MB per-image budget while the
# marker retains the native screen scale and SwiftUI image frame used for
# coordinate comparisons.
sips -Z 2000 "$SCREENSHOT_PATH" >/dev/null
xcrun simctl spawn "$DEVICE_ID" /bin/cat "$MARKER_PATH" > "$EVIDENCE_DIR/metadata/$MARKER_NAME"

python3 - "$EVIDENCE_DIR/metadata/$MARKER_NAME" "$SCREENSHOT_PATH" "$FIXTURE_NAME" "$REPO_ROOT/TestFixtures/TradingCards/GroundTruth/$FIXTURE_NAME.gt.json" <<'PY'
import json
import math
import sys
from pathlib import Path

marker_path, screenshot_path, fixture, ground_truth_path = sys.argv[1:]
marker = json.loads(Path(marker_path).read_text(encoding="utf-8"))
ground_truth = json.loads(Path(ground_truth_path).read_text(encoding="utf-8"))
marker["fixture"] = fixture
marker["screenshotPath"] = screenshot_path
marker["screenshotPixelSize"] = {"width": None, "height": None}
try:
    from PIL import Image
    with Image.open(screenshot_path) as image:
        marker["screenshotPixelSize"] = {"width": image.width, "height": image.height}
except ImportError:
    pass

def point(values):
    if isinstance(values, dict):
        return {"x": float(values["x"]), "y": float(values["y"])}
    return {"x": float(values[0]), "y": float(values[1])}

def quad_points(values):
    if isinstance(values, dict):
        return [values[key] for key in ("topLeft", "topRight", "bottomRight", "bottomLeft")]
    return values

def rotate(value, degrees, source_size, destination_size):
    radians = math.radians(degrees)
    cosine = math.cos(radians)
    sine = math.sin(radians)
    dx = value["x"] - source_size["width"] / 2
    dy = value["y"] - source_size["height"] / 2
    return {
        "x": destination_size["width"] / 2 + cosine * dx - sine * dy,
        "y": destination_size["height"] / 2 + sine * dx + cosine * dy,
    }

def map_native_to_working(value, mapping):
    source = mapping["orientedSourceSize"]
    unrotated = mapping.get("unrotatedWorkingSize", mapping["workingSize"])
    working = mapping["workingSize"]
    scaled = {
        "x": value["x"] * unrotated["width"] / source["width"],
        "y": value["y"] * unrotated["height"] / source["height"],
    }
    return rotate(scaled, mapping.get("appliedRotationDegrees", 0), unrotated, working)

def map_quad(values, mapper):
    return [mapper(point(value)) for value in quad_points(values)]

def to_screen(value, frame, image_size):
    return {
        "x": frame["x"] + value["x"] * frame["width"] / image_size["width"],
        "y": frame["y"] + value["y"] * frame["height"] / image_size["height"],
    }

def screen_quad(values, frame, image_size):
    return [to_screen(point(value), frame, image_size) for value in quad_points(values)]

def max_corner_delta(first, second):
    if not first or not second or len(first) != len(second):
        return None
    return max(
        math.hypot(lhs["x"] - rhs["x"], lhs["y"] - rhs["y"])
        for lhs, rhs in zip(first, second)
    )

def ratio_value(value):
    if not value or value == "—" or " / " not in value:
        return None
    return float(value.split(" / ", 1)[0])

frame = marker.get("presentedImageFrame")
mapping = marker.get("coordinateMapping")
if frame and mapping:
    image_size = mapping["workingSize"]
    gt_outer_working = map_quad(ground_truth["cardOuterQuad"], lambda p: map_native_to_working(p, mapping))
    gt_inner_working = None
    if ground_truth.get("innerQuad") is not None:
        gt_inner_working = map_quad(ground_truth["innerQuad"], lambda p: map_native_to_working(p, mapping))
    detected_outer = marker.get("outerQuad")
    detected_inner = marker.get("innerQuad")
    gt_outer_screen = screen_quad(gt_outer_working, frame, image_size)
    gt_inner_screen = screen_quad(gt_inner_working, frame, image_size) if gt_inner_working else None
    detected_outer_screen = screen_quad(detected_outer, frame, image_size) if detected_outer else None
    detected_inner_screen = screen_quad(detected_inner, frame, image_size) if detected_inner else None
    expected_lr = ground_truth.get("expected", {}).get("lrRatio")
    expected_tb = ground_truth.get("expected", {}).get("tbRatio")
    actual_lr = ratio_value(marker.get("leftRightCentering"))
    actual_tb = ratio_value(marker.get("topBottomCentering"))
    marker["coordinateSpace"] = "CardCenteringImage local points; frame is SwiftUI points; screenshot pixels are recorded separately"
    marker["groundTruthMappedScreen"] = {"outer": gt_outer_screen, "inner": gt_inner_screen}
    marker["detectedMappedScreen"] = {"outer": detected_outer_screen, "inner": detected_inner_screen}
    marker["metricDeltas"] = {
        "outerCornerMaxScreenPoints": max_corner_delta(detected_outer_screen, gt_outer_screen),
        "innerCornerMaxScreenPoints": max_corner_delta(detected_inner_screen, gt_inner_screen),
        "leftRightRatioDeltaPp": abs(actual_lr - expected_lr) if actual_lr is not None and expected_lr is not None else None,
        "topBottomRatioDeltaPp": abs(actual_tb - expected_tb) if actual_tb is not None and expected_tb is not None else None,
    }

Path(marker_path).write_text(json.dumps(marker, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(marker, indent=2, sort_keys=True))
PY
