#!/bin/bash
set -e
REPO="$(git rev-parse --show-toplevel)"
HARNESS="$REPO/review/centering-harness"
cd "$HARNESS"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p build && cp meta_main.swift build/main.swift
mkdir -p "$REPO/artifacts/centering-baseline"
xcrun -sdk iphonesimulator swiftc -O -target arm64-apple-ios18.0-simulator -sdk "$SDK" \
  build/main.swift \
  "$REPO/TradingCardScanner/Services/CardCenteringAnalyzer.swift" \
  "$REPO/TradingCardScanner/Models/CardCenteringMeasurement.swift" \
  -o build/meta
xcrun simctl spawn booted "$(pwd)/build/meta" "$REPO/TestFixtures/TradingCards/HEIC" \
  > "$REPO/artifacts/centering-baseline/metamorphic.csv" 2>&1
echo "DONE $?"
