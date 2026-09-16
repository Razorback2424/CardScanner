#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
output_directory="${1:-$project_root/TradingCardScanner/PokemonChecklistSnapshot}"
destination="${POKEMON_SNAPSHOT_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
derived_data_path="${POKEMON_SNAPSHOT_DERIVED_DATA_PATH:?POKEMON_SNAPSHOT_DERIVED_DATA_PATH must point to the external-SSD DerivedData directory}"
result_bundle_path="${POKEMON_SNAPSHOT_RESULT_BUNDLE_PATH:-$derived_data_path/pokemon-snapshot.xcresult}"
temporary_directory="${POKEMON_SNAPSHOT_TMPDIR:-$derived_data_path/tmp}"
module_cache_path="${POKEMON_SNAPSHOT_MODULE_CACHE_PATH:-$derived_data_path/ModuleCache.noindex}"
mkdir -p "$output_directory"
mkdir -p "$temporary_directory"
mkdir -p "$module_cache_path"

cd "$project_root"
TMPDIR="$temporary_directory" \
CLANG_MODULE_CACHE_PATH="$module_cache_path" \
SWIFT_MODULECACHE_PATH="$module_cache_path" \
POKEMON_SNAPSHOT_OUTPUT="$output_directory" xcodebuild \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "$destination" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  -only-testing:TradingCardScannerTests/BrowseFeatureTests/testGeneratePokemonChecklistSnapshotWhenRequested \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  POKEMON_SNAPSHOT_OUTPUT="$output_directory" \
  INFOPLIST_KEY_POKEMON_SNAPSHOT_OUTPUT="$output_directory" \
  test
