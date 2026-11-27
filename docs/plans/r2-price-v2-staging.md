# Stage 2 — immutable market price builds and Firebase rollback

**Status, November 27, 2026.** The first R2 staging run verified all 2,886
objects and preserved 68,239 priced product and finish combinations across
the four mirrored games. The app client passed live staging checks. Firebase
rollback support is implemented in the candidate and awaits deployment
evidence. The publisher derives v2 from the same validated v1 capture on both
hosts. See the [first staging run](https://github.com/Razorback2424/CardScanner/actions/runs/46009309602)
and [app client notes](r2-price-v2-client.md).

The v2 price namespace exposes the following files.

- market-prices/v2/latest.json: schemaVersion 2, sourceBuild, build, files.
- market-prices/v2/builds/<build>/<path>: exact captured v1 feed bytes,
  index.json, last-updated.txt, and scopes/{one-piece,yugioh}.json.
- build is SHA-256 of the canonical pointer document without the build field
  (sorted JSON keys, compact separators, UTF-8, final newline). Each files
  entry binds a relative path, SHA-256 and byteCount. A corrected same-day
  capture gets a distinct identity. No data is deleted.

The R2 job verifies actual priced-product/finish coverage for all four mirrored
categories against the same v1 capture using catalog_parity.py. It stages
immutable objects, verifies public bytes and headers even for unchanged
objects, then confirms the artifact is still current on Firebase and checks
the existing R2 pointer before activating v2. The workflow is serialized.
Only then does it update R2's existing v1 paths, with the v1 marker last.
A failed v1 publish leaves a complete v2 build available; rerunning the
same still-current artifact repairs it, including skipped mutable price
objects whose metadata matched but whose public readback did not. Immutable
objects are never repaired by overwriting different bytes; failed integrity
checks stop publication. Pointer preflight and post-write readback use
distinct cache-busting URLs. An explicitly authorized empty catalog price
scope may omit that game's feed groups; unexpected missing or extra scope
groups stop publication. Superseded artifacts are rejected.

## Firebase rollback compatibility

The first price run inventories R2's existing v2 build prefixes under the
R2 publishing lock. It imports each complete build through the public
staging hostname, checks its address and every file, and includes the active
R2 build even if it advanced after the inventory. An incomplete inventory or
build blocks deployment and requires investigation. The R2 credential needs
bucket list access for the bootstrap.

Firebase hosts `market-prices/v2/history.json` with the retained build IDs.
Every shared-site deployment restores those builds and verifies every file
before deploying. A catalog-only deployment carries the active pointer
forward byte for byte. Each successful price deployment appends its new build
and verifies public Firebase history and the active pointer before handing the
capture to R2. R2 checks that the Firebase pointer matches its candidate
before activation and again before reporting success. Firebase can lead R2
during publication or after a failed mirror. The earlier R2 build stays
available on Firebase during that interval. A parity check must pass before
using Firebase as an active fallback for production v2 clients.

Before shipping production v2, complete a live Firebase bootstrap, confirm a
subsequent catalog-only deployment still serves an earlier referenced build,
and rehearse directing a v2 client to Firebase with matching active pointers.
Confirm both origins serve JSON and text with the intended cache headers.
Cloudflare cache-rule checks, the seven-day parallel validation, and production
DNS cutover remain open. Production clients still use v1. The workflow remains
Firebase-first and retains all builds. Track restoration time and transfer as
history grows before setting a retention policy.
