#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "usage: $0 POKEMON_POINTER_PATH MAGIC_POINTER_PATH SITE_ROOT ORIGIN [POKEMON_PACKAGE] [POKEMON_KEYS] [MAGIC_PACKAGE] [MAGIC_KEYS] [ONE_PIECE_POINTER_PATH] [ONE_PIECE_PACKAGE] [ONE_PIECE_KEYS]" >&2
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
one_piece_active_path="${9:-}"
one_piece_package="${10:-OnePieceCatalogCore}"
one_piece_keys="${11:-Config/OnePieceCatalogProduction.xcconfig}"
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
  if [ "$publisher_command" = "one-piece-catalog-publisher" ]; then
    local exported_keys
    exported_keys="$(mktemp "${RUNNER_TEMP:-/tmp}/one-piece-pinned-keys.XXXXXX")"
    python3 scripts/one_piece_pinned_keys.py "$trusted_keys_file" "$exported_keys"
    local one_piece_arguments=(--package-path "$package_path" "$publisher_command"
      verify-hosted-release --input "$release_path" --trusted-keys "$exported_keys")
    if [ -n "$expected_revision" ]; then
      one_piece_arguments+=(--expected-revision "$expected_revision")
    fi
    local result
    if ! result="$(swift run "${one_piece_arguments[@]}")"; then
      rm -f "$exported_keys"
      return 1
    fi
    rm -f "$exported_keys"
    printf '%s\n' "$result"
    return 0
  fi
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
    for file in ${release_files[@]+"${release_files[@]}"}; do
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

    local destination="$site_root/$namespace/releases/$revision"
    mkdir -p "$destination"
    for file in catalog-release.json ${release_files[@]+"${release_files[@]}"}; do
      if [ -f "$destination/$file" ]; then
        cmp "$temporary_release/$file" "$destination/$file" >/dev/null || {
          echo "Refusing to overwrite immutable $namespace revision $revision artifact $file" >&2
          exit 1
        }
      else
        cp "$temporary_release/$file" "$destination/$file"
      fi
    done
    restored=$((restored + 1))
  done

  if [ "$namespace" = "one-piece/v1" ]; then
    cmp "$active_path" "$site_root/$namespace/releases/$current_revision/catalog-release.json" >/dev/null || {
      echo "One Piece pointer must match its verified immutable revision" >&2
      exit 1
    }
  fi

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

# Existing Pokémon/Magic publishers need no new argument: preserve any
# independently published One Piece namespace before their complete-site deploy.
if [ -z "$one_piece_active_path" ]; then
  one_piece_active_path="$(mktemp "${RUNNER_TEMP:-/tmp}/one-piece-current.XXXXXX")"
  trap 'rm -f "$one_piece_active_path"' EXIT
  status="$(curl --location --proto '=https' --tlsv1.2 --max-redirs 3 --silent --show-error \
    --output "$one_piece_active_path" --write-out '%{http_code}' "$origin/one-piece/v1/current.json")"
  if [ "$status" = "404" ]; then
    rm -f "$one_piece_active_path"
  elif [ "$status" != "200" ]; then
    echo "Unexpected HTTP $status while reading the One Piece production pointer" >&2
    exit 1
  fi
fi
restore_namespace "$one_piece_active_path" "one-piece/v1" "$one_piece_package" "$one_piece_keys" \
  "one-piece-catalog-publisher"
