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

jq -e '
  .hosting
  | map(select(.target == "production" and .public == "publisher/site"))
  | .[0].headers
  | (map(select(.source == "/v1/current.json" and
               ([.headers[]? | select(.key == "Cache-Control" and .value == "no-cache")] | length) == 1)) | length == 1)
    and
    (map(select(.source == "/v1/releases/**" and
               ([.headers[]? | select(.key == "Cache-Control" and .value == "public,max-age=31536000,immutable")] | length) == 1)) | length == 1)
    and
    (map(select(.source == "/magic/v1/current.json" and
               ([.headers[]? | select(.key == "Cache-Control" and .value == "no-cache")] | length) == 1)) | length == 1)
    and
    (map(select(.source == "/magic/v1/releases/**" and
               ([.headers[]? | select(.key == "Cache-Control" and .value == "public,max-age=31536000,immutable")] | length) == 1)) | length == 1)
' firebase.json >/dev/null

echo "Firebase Hosting production target, dot-file ignore, and four catalog cache classes are valid"
