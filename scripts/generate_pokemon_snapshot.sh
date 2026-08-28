#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
output_directory="${1:-$project_root/TradingCardScanner/PokemonChecklistSnapshot}"
destination="${POKEMON_SNAPSHOT_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
mkdir -p "$output_directory"

cd "$project_root"
POKEMON_SNAPSHOT_OUTPUT="$output_directory" xcodebuild \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "$destination" \
  -only-testing:TradingCardScannerTests/BrowseFeatureTests/testGeneratePokemonChecklistSnapshotWhenRequested \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  test
