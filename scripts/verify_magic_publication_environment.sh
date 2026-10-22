#!/usr/bin/env bash
set -euo pipefail

# Presence check only. Signing authorization, key validity and Firebase access
# remain enforced by the publisher and deployment commands.
missing=0
for name in MAGIC_CATALOG_SIGNING_KEY MAGIC_CATALOG_KEY_ID \
  FIREBASE_SERVICE_ACCOUNT FIREBASE_PROJECT_ID FIREBASE_HOSTING_SITE_ID; do
  if [ -z "${!name:-}" ]; then
    echo "Missing required publication variable: $name" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  case "${GITHUB_ENVIRONMENT:-}" in
    magic-catalog-production|magic-catalog-production-auto)
      echo "Check secret availability in the selected GitHub environment: $GITHUB_ENVIRONMENT" >&2
      ;;
    *) echo "Check the selected Magic publication environment in GitHub Actions." >&2 ;;
  esac
  echo "Verify environment/repository secret scope and workflow bindings before retrying publication." >&2
  exit 1
fi
