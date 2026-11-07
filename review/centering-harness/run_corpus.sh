#!/bin/bash
set -euo pipefail
# Explicit output location keeps generated data on the preferred external SSD.
if [[ $# != 2 ]]; then
  echo 'usage: run_corpus.sh OUTPUT_DIRECTORY BOOTED_SIMULATOR_UDID' >&2
  exit 2
fi
REPO="$(git rev-parse --show-toplevel)"
OUTPUT="$1"
SIMULATOR="$2"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
mkdir -p "$OUTPUT/build" "$OUTPUT/cache"
cp "$REPO/review/centering-harness/corpus_main.swift" "$OUTPUT/build/main.swift"
xcrun --sdk iphonesimulator clang -O2 -target arm64-apple-ios18.0-simulator \
  -isysroot "$SDK_PATH" -c "$REPO/TradingCardScanner/Services/CardCenteringPixelKernels.c" \
  -o "$OUTPUT/build/pixels.o"
xcrun --sdk iphonesimulator swiftc -O -target arm64-apple-ios18.0-simulator \
  -sdk "$SDK_PATH" -module-cache-path "$OUTPUT/cache" \
  -import-objc-header "$REPO/TradingCardScanner/Services/CardCenteringPixelKernels.h" \
  "$OUTPUT/build/main.swift" "$OUTPUT/build/pixels.o" \
  "$REPO/TradingCardScanner/Services/CardCenteringAnalyzer.swift" \
  "$REPO/TradingCardScanner/Models/CardCenteringMeasurement.swift" \
  "$REPO/TradingCardScanner/Models/CardCenteringBoundaryEvidence.swift" \
  "$REPO/TradingCardScanner/Models/CardCenteringSpatialMeasurement.swift" \
  -o "$OUTPUT/build/corpus"
xcrun simctl spawn "$SIMULATOR" "$OUTPUT/build/corpus" \
  "$REPO/review/centering-evidence/existing-corpus-status-2026-11-05.json" \
  "$REPO/TestFixtures/TradingCards/HEIC" "$OUTPUT"
