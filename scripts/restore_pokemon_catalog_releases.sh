#!/usr/bin/env bash
set -euo pipefail

active_path="${1:?usage: $0 ACTIVE_POINTER_PATH SITE_ROOT ORIGIN [PACKAGE_PATH] [TRUSTED_KEYS_FILE]}"
site_root="${2:?usage: $0 ACTIVE_POINTER_PATH SITE_ROOT ORIGIN [PACKAGE_PATH] [TRUSTED_KEYS_FILE]}"
origin="${3:?usage: $0 ACTIVE_POINTER_PATH SITE_ROOT ORIGIN [PACKAGE_PATH] [TRUSTED_KEYS_FILE]}"
publisher_package="${4:-PokemonCatalogCore}"
trusted_keys_file="${5:-Config/PokemonCatalogProduction.xcconfig}"
namespace="v1"
expected_site_root="publisher/site"
max_restore_revision=100000

if [ "$origin" != "https://scanstash-catalog-prod.web.app" ]; then
  echo "unexpected production catalog restore origin: $origin" >&2
  exit 2
fi

if [ "$site_root" != "$expected_site_root" ]; then
  echo "site root $site_root is not the production catalog site root" >&2
  exit 2
fi

if [ ! -f "$active_path" ]; then
  echo "No active production catalog release exists; starting a new site tree"
  exit 0
fi

verify_release() {
  local release_path="$1"
  local expected_revision="${2:-}"
  local arguments=(
    --package-path "$publisher_package"
    pokemon-catalog-publisher
    verify-release
    --path "$release_path"
    --environment production
    --trusted-keys-file "$trusted_keys_file"
  )
  if [ -n "$expected_revision" ]; then
    arguments+=(--expected-revision "$expected_revision")
  fi
  swift run "${arguments[@]}"
}

current_revision="$(verify_release "$active_path")"
if [ "$current_revision" -lt 1 ] || [ "$current_revision" -gt "$max_restore_revision" ]; then
  echo "active catalog pointer revision is outside the safe restore range: $current_revision" >&2
  exit 1
fi

runner_temp="${RUNNER_TEMP:-/tmp}"
restore_root="${runner_temp}/pokemon-catalog-production-releases"
rm -rf "$restore_root"
mkdir -p "$restore_root"
mkdir -p "$site_root/$namespace/releases"
restored=0

for revision in $(seq 1 "$current_revision"); do
  temporary_release="$restore_root/$revision"
  mkdir -p "$temporary_release"
  release_url="$origin/$namespace/releases/$revision"

  if ! status="$(curl --location --proto '=https' --tlsv1.2 --max-redirs 3 --silent --show-error \
    --output "$temporary_release/catalog-release.json" \
    --write-out '%{http_code}' \
    "$release_url/catalog-release.json")"; then
    echo "Failed to read production revision $revision" >&2
    exit 1
  fi
  if [ "$status" = "404" ]; then
    rm -rf "$temporary_release"
    continue
  fi
  if [ "$status" != "200" ]; then
    echo "Unexpected HTTP $status while reading production revision $revision" >&2
    exit 1
  fi

  verify_release "$temporary_release/catalog-release.json" "$revision" >/dev/null

  for file in catalog-payload.json pokemon-catalog-snapshot.json review-report.json; do
    if ! status="$(curl --location --proto '=https' --tlsv1.2 --max-redirs 3 --silent --show-error \
      --output "$temporary_release/$file" \
      --write-out '%{http_code}' \
      "$release_url/$file")"; then
      echo "Failed to read $file for production revision $revision" >&2
      exit 1
    fi
    if [ "$status" != "200" ]; then
      echo "Unexpected HTTP $status while reading $file for production revision $revision" >&2
      exit 1
    fi
  done

  mv "$temporary_release" "$site_root/$namespace/releases/$revision"
  restored=$((restored + 1))
done

mkdir -p "$site_root/$namespace"
cp -f "$active_path" "$site_root/$namespace/current.json"

echo "Restored $restored previously published production catalog revision object(s) through revision $current_revision"
