#!/bin/bash
set -e

REPO="$(git rev-parse --show-toplevel)"
HARNESS="$REPO/review/centering-harness"
cd "$HARNESS"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p build
cp sensitivity_main.swift build/main.swift

xcrun -sdk iphonesimulator swiftc -DDEBUG -O \
  -target arm64-apple-ios18.0-simulator -sdk "$SDK" \
  build/main.swift \
  "$REPO/TradingCardScanner/Services/CardCenteringAnalyzer.swift" \
  "$REPO/TradingCardScanner/Models/CardCenteringMeasurement.swift" \
  -o build/sensitivity

OUTPUT_DIR="${OUTPUT_DIR:-$REPO/artifacts/centering-sensitivity}"
mkdir -p "$OUTPUT_DIR"
xcrun simctl spawn booted "$HARNESS/build/sensitivity" \
  "$REPO/TestFixtures/TradingCards/HEIC" \
  "$OUTPUT_DIR"
echo "WROTE $OUTPUT_DIR/numerical-sensitivity.json"
