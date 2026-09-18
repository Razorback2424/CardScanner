#!/usr/bin/env bash
set -euo pipefail

active_path="${1:?usage: $0 ACTIVE_POINTER_PATH SITE_ROOT}"
site_root="${2:?usage: $0 ACTIVE_POINTER_PATH SITE_ROOT}"
origin="https://catalog.scan-stash.com"
namespace="v1"
expected_site_root="publisher/site"

if [ "$site_root" != "$expected_site_root" ]; then
  echo "site root $site_root is not the production catalog site root" >&2
  exit 2
fi

if [ ! -f "$active_path" ]; then
  echo "No active production catalog release exists; starting a new site tree"
  exit 0
fi

current_revision="$(python3 - "$active_path" <<'PY'
import base64
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    envelope = json.load(handle)
payload = envelope.get("payload")
if not isinstance(payload, str) or not payload:
    raise SystemExit("active catalog pointer has no payload")
try:
    release = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
except Exception as error:
    raise SystemExit(f"active catalog pointer payload is invalid: {error}")
revision = release.get("revision")
if not isinstance(revision, int) or revision < 1:
    raise SystemExit("active catalog pointer has an invalid revision")
print(revision)
PY
)"

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

  if ! status="$(curl --location --silent --show-error \
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

  for file in catalog-payload.json pokemon-catalog-snapshot.json review-report.json; do
    if ! status="$(curl --location --silent --show-error \
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

echo "Restored $restored previously published production catalog revision object(s) through revision $current_revision"
