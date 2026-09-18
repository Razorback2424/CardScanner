#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "jq is required to validate firebase.json" >&2
  exit 1
}

jq -e \
  '.hosting
   | [ .[]
       | select(.target == "production")
       | select(.public == "publisher/site")
       | select((.ignore | index("**/.*")) != null)
     ]
   | length == 1' \
  firebase.json >/dev/null

echo "Firebase Hosting production target and dot-file ignore are valid"
