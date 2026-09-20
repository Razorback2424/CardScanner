#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "usage: $0 POKEMON_POINTER_PATH MAGIC_POINTER_PATH SITE_ROOT ORIGIN [POKEMON_PACKAGE] [POKEMON_KEYS] [MAGIC_PACKAGE] [MAGIC_KEYS]" >&2
  exit 2
fi

pokemon_active_path="$1"
magic_active_path="$2"
site_root="$3"
origin="$4"

pokemon_package="${5:-PokemonCatalogCore}"
pokemon_keys="${6:-Config/PokemonCatalogProduction.xcconfig}"
magic_package="${7:-MagicCatalogCore}"
magic_keys="${8:-Config/MagicCatalogProduction.xcconfig}"
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

verify_release() {
  local package_path="$1"
  local publisher_command="$2"
  local release_path="$3"
  local trusted_keys_file="$4"
  local expected_revision="${5:-}"
  local arguments=(
    --package-path "$package_path"
    "$publisher_command"
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

restore_namespace() {
  local active_path="$1"
  local namespace="$2"
  local package_path="$3"
  local trusted_keys_file="$4"
  local publisher_command="$5"
  shift 5
  local -a release_files=("$@")

  if [ -z "$active_path" ] || [ ! -f "$active_path" ]; then
    echo "No active production release exists for $namespace; leaving that namespace absent"
    return 0
  fi

  local current_revision
  current_revision="$(verify_release "$package_path" "$publisher_command" "$active_path" "$trusted_keys_file")"
  if [ "$current_revision" -lt 1 ] || [ "$current_revision" -gt "$max_restore_revision" ]; then
    echo "$namespace pointer revision is outside the safe restore range: $current_revision" >&2
    exit 1
  fi

  local runner_temp="${RUNNER_TEMP:-/tmp}"
  local restore_root="$runner_temp/catalog-hosting-restore-$namespace"
  rm -rf "$restore_root"
  mkdir -p "$restore_root"
  mkdir -p "$site_root/$namespace/releases"
  local restored=0

  local revision
  for revision in $(seq 1 "$current_revision"); do
    local temporary_release="$restore_root/$revision"
    mkdir -p "$temporary_release"
    local release_url="$origin/$namespace/releases/$revision"

    local status
    if ! status="$(curl --location --proto '=https' --tlsv1.2 --max-redirs 3 --silent --show-error \
      --output "$temporary_release/catalog-release.json" \
      --write-out '%{http_code}' \
      "$release_url/catalog-release.json")"; then
      echo "Failed to read $namespace production revision $revision" >&2
      exit 1
    fi
    if [ "$status" = "404" ]; then
      rm -rf "$temporary_release"
      continue
    fi
    if [ "$status" != "200" ]; then
      echo "Unexpected HTTP $status while reading $namespace production revision $revision" >&2
      exit 1
    fi

    verify_release "$package_path" "$publisher_command" \
      "$temporary_release/catalog-release.json" "$trusted_keys_file" "$revision" >/dev/null

    local file
    for file in "${release_files[@]}"; do
      if ! status="$(curl --location --proto '=https' --tlsv1.2 --max-redirs 3 --silent --show-error \
        --output "$temporary_release/$file" \
        --write-out '%{http_code}' \
        "$release_url/$file")"; then
        echo "Failed to read $file for $namespace production revision $revision" >&2
        exit 1
      fi
      if [ "$status" != "200" ]; then
        echo "Unexpected HTTP $status while reading $file for $namespace production revision $revision" >&2
        exit 1
      fi
    done

    mv "$temporary_release" "$site_root/$namespace/releases/$revision"
    restored=$((restored + 1))
  done

  mkdir -p "$site_root/$namespace"
  cp -f "$active_path" "$site_root/$namespace/current.json"
  echo "Restored $restored $namespace production revision object(s) through revision $current_revision"
}

restore_namespace \
  "$pokemon_active_path" \
  "v1" \
  "$pokemon_package" \
  "$pokemon_keys" \
  "pokemon-catalog-publisher" \
  catalog-payload.json pokemon-catalog-snapshot.json review-report.json

restore_namespace \
  "$magic_active_path" \
  "magic/v1" \
  "$magic_package" \
  "$magic_keys" \
  "magic-catalog-publisher" \
  catalog-payload.json review-report.json
