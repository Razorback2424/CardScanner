# Stage 2 — R2-first catalog and price publication with Firebase rollback

**Status, November 27, 2026.** The first R2 staging run verified all 2,886
objects and preserved 68,239 priced product and finish combinations across
the four mirrored games. The app client passed live staging checks. Both
market price publication (PR #74) and catalog publication across Pokémon,
One Piece, Magic, and Yu-Gi-Oh! (PR #75) are now structured R2-first with
independent Firebase backup and catch-up. Live acceptance of the R2-first
workflows remains open. See the
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
lock (`scanstash-catalog-r2-hosting`, queued FIFO) covers scope capture
through activation and serializes price updates against catalog updates.

The publisher compares priced product and finish coverage across all four
mirrored games, verifies every immutable object, records the verified build
and then updates the active pointer. R2 v1 is updated afterward, with its
marker last. A failure updating v1 leaves a complete v2 build available. A
subsequent primary run can repair corrupted mutable prices from its verified
capture. A corrupt immutable build blocks activation. Pointer preflight and
post-write readback use distinct cache-busting URLs.

## Primary R2 catalog publication

All catalog publication workflows (`pokemon-catalog.yml`,
`one-piece-catalog.yml`, `magic-catalog.yml`, and the local One Piece
fallback `scripts/publish_one_piece_local.py`) now publish directly to R2
before any Firebase backup runs:

- Active pointers are read from `https://catalog-staging.scan-stash.com`
  with cache-bypass headers and query nonces. Signing keys, pinned public
  keys, change-class rules, approval environments, size preflight, and
  revision monotonicity are unchanged.
- Each signing/staging job produces only its own catalog namespace plus a
  canonical `catalog-publish-metadata.json` binding the revision, its exact
  predecessor pointer SHA-256, immutable release files, and (for One Piece
  and Yu-Gi-Oh!) its revision-bound `market-price-scope.json`. Neither
  staging nor primary R2 publication depends on Firebase credentials or
  Firebase reachability.
- `scripts/r2_catalog_publish.py --primary-catalog <namespace>` runs under
  `r2-catalog-production` and `scanstash-catalog-r2-hosting`. It refuses
  files outside the target namespace (including `market-prices/`), confirms
  R2's active pointer and predecessor immutable release, uploads and
  publicly hash-verifies every immutable release object first, re-checks
  the active pointer, updates `market-price-scope.json` when applicable,
  and activates `current.json` last. Historical revisions are never deleted
  or overwritten.
- If a scoped catalog publish is interrupted between `market-price-scope.json`
  and `current.json`, the primary price job can still fall back to the
  hash-verified scope inside its current v2 price build while the catalog
  pointer stays on the prior revision.
- Firebase-originated catalog synchronization (`mirror-catalogs-to-r2`) has
  been removed; R2 is the sole primary origin for both catalogs and prices.
  `yugioh-catalog.yml` also allows `YUGIOH_APPROVED_PARENT_URL` to point at
  `https://catalog-staging.scan-stash.com/yugioh/v1/current.json`.

## Firebase rollback compatibility

After R2 readback succeeds, each catalog or price workflow runs an
independent Firebase backup job under `scanstash-catalog-production-hosting`.
Firebase backup failures are reported visibly in their own job and leave
the verified R2 publication active.

- All Firebase backups restore every catalog namespace and full revision
  history from R2 (`scripts/catalog_hosting_cache.py` and
  `scripts/restore_catalog_hosting_site.sh`), verifying every revision
  against app-pinned public keys.
- Price backups (`yugioh-catalog.yml`) reconstruct and verify the exact R2
  price build via `market_price_rollback.py prepare`, confirming R2 catalog
  pointers and scopes still match before deployment.
- Catalog backups (`pokemon-catalog.yml`, `one-piece-catalog.yml`,
  `magic-catalog.yml`) synchronize retained and missed R2 v2 price builds
  via `market_price_rollback.py sync-r2` without requiring a new price
  capture when a freshly published catalog advances its scope ahead of the
  latest price build. Both price and catalog backups preserve any
  Firebase-only pre-R2 builds recorded in `market-prices/v2/history.json`.
- Before and after `firebase deploy`, backups confirm R2 catalog pointers,
  scopes, and the active R2 v2 price pointer match the staged deployment,
  and verify Firebase readback bytes and cache headers for pointers,
  scopes, new immutable releases, v1 prices, and v2 price history.
- R2 can advance across multiple catalog and price publications during a
  complete Firebase outage; the next successful backup catches Firebase up
  from R2 with all missed catalog revisions and price builds.

## Outstanding live acceptance requirements

Before enabling production v2 clients or cutting over production DNS:

1. Ensure R2 staging already holds the latest verified Firebase catalog
   revisions before merging PR #75 live (already mirrored by PR #69/#74).
2. Complete a live Firebase v2 bootstrap and verify a qualifying R2-first
   price run plus a qualifying R2-first catalog publish (confirming
   immutable release readback before pointer flip, scope parity, and
   Firebase backup readback with preserved earlier v2 builds and historical
   catalog revisions).
3. Rehearse a simulated Firebase backup failure/outage and subsequent
   catch-up run confirming R2 stays active and Firebase recovers every
   missed catalog revision and v2 price build.
4. Rehearse directing a v2 client to Firebase with matching active
   pointers and confirm both origins serve JSON and text with the intended
   cache headers.
5. Complete Cloudflare cache-rule verification and pointer purging (PR #76),
   continuous rollback readiness/certificate/quota checks and roll-forward
   rehearsal (PR #77), Magic hostname/production v2 client config (PR #78),
   the seven-day parallel publication period, and production DNS cutover.
   Production clients remain on v1 until those gates pass. The workflow
   retains all builds; track restoration time and transfer as history grows
   before setting a retention policy.
