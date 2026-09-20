#!/usr/bin/env bash
set -euo pipefail

active_path="${1:?usage: $0 ACTIVE_POINTER_PATH SITE_ROOT ORIGIN [PACKAGE_PATH] [TRUSTED_KEYS_FILE]}"
site_root="${2:?usage: $0 ACTIVE_POINTER_PATH SITE_ROOT ORIGIN [PACKAGE_PATH] [TRUSTED_KEYS_FILE]}"
origin="${3:?usage: $0 ACTIVE_POINTER_PATH SITE_ROOT ORIGIN [PACKAGE_PATH] [TRUSTED_KEYS_FILE]}"
publisher_package="${4:-PokemonCatalogCore}"
trusted_keys_file="${5:-Config/PokemonCatalogProduction.xcconfig}"

exec bash "$(dirname "$0")/restore_catalog_hosting_site.sh" \
  "$active_path" \
  "" \
  "$site_root" \
  "$origin" \
  "$publisher_package" \
  "$trusted_keys_file" \
  MagicCatalogCore \
  Config/MagicCatalogProduction.xcconfig
