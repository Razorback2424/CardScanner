# Stage 2 — immutable market price builds and Firebase rollback

**Status, November 27, 2026.** The first R2 staging run verified all 2,886
objects and preserved 68,239 priced product and finish combinations across
the four mirrored games. The app client passed live staging checks. The
R2-first candidate depends on the Firebase rollback implementation. Live
acceptance of the new workflow remains open. See the
[first staging run](https://github.com/Razorback2424/CardScanner/actions/runs/46009309602)
and [app client notes](r2-price-v2-client.md).

The v2 price namespace exposes the following files.

- market-prices/v2/latest.json: schemaVersion 2, sourceBuild, build, files.
- market-prices/v2/builds/<build>/<path>: exact captured v1 feed bytes,
  index.json, last-updated.txt, and scopes/{one-piece,yugioh}.json.
- build is SHA-256 of the canonical pointer document without the build field
  (sorted JSON keys, compact separators, UTF-8, final newline). Each files
  entry binds a relative path, SHA-256 and byteCount. A corrected same-day
  capture gets a distinct identity. No data is deleted.

## Primary R2 pricing

The primary job captures TCGCSV prices against scopes bound to R2's active
catalogs. The job needs the provider and R2. The separate catalog candidate
job and Firebase can both fail while R2 pricing succeeds. The R2 publishing
lock covers the scope capture through activation.

The publisher compares priced product and finish coverage across all four
mirrored games, verifies every immutable object, records the verified build
and then updates the active pointer. R2 v1 is updated afterward, with its
marker last. A failure updating v1 leaves a complete v2 build available. A
subsequent primary run can repair corrupted mutable prices from its verified
capture. A corrupt immutable build blocks activation. Pointer preflight and
post-write readback use distinct cache-busting URLs.

The catalog-only sync keeps Firebase catalog releases and their price scopes
moving to R2 after the primary run. When the two hosts have different active
catalog scopes, the backup reports the discrepancy and the catalog-only sync
can carry the new catalog to R2 for the next price capture. If that sync stops
between a scope write and its catalog pointer, the primary job can use the
hash-verified scope from its current v2 build when it still binds to the
active catalog.

## Firebase rollback compatibility

After R2 readback succeeds, the backup inventories verified R2 builds and
adds any builds missed during prior backup failures. A first bootstrap uses
the legacy build inventory. The R2 credential needs bucket list access for
the inventory. Firebase hosts `market-prices/v2/history.json` with the
retained build IDs. Shared Firebase deployments restore those builds and
verify their files before deploying. The price backup restores retained
bytes from R2 where available to reduce Firebase reads.

The backup reconstructs the exact build verified on R2, checks that it is
still active before deployment, and verifies Firebase's public files and
pointer afterward. Firebase backup failures remain visible in their own job.
R2 can advance during a Firebase outage, leaving the last verified Firebase
backup available until a successful catch-up run. Both active pointers must
match before using Firebase as a fallback for production v2 clients.

Before shipping production v2, complete a live Firebase bootstrap, confirm a
subsequent catalog-only deployment still serves an earlier referenced build,
and rehearse directing a v2 client to Firebase with matching active pointers.
Confirm both origins serve JSON and text with the intended cache headers.
Cloudflare cache-rule checks, the seven-day parallel validation, and production
DNS cutover remain open. Production clients still use v1. The workflow
retains all builds. Track restoration time and transfer as history grows
before setting a retention policy.
